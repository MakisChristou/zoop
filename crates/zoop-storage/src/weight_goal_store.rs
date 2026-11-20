//! Opt-in, revisioned goals and bounded source-preserving daily weight inputs.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::HealthSync, e)
}

/// Settings belong to the authenticated device dataset; edits preserve an audit revision.
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct WeightGoal {
    /// Stable identity of this phase, independent of its settings revisions.
    pub id: i64,
    /// Cut, bulk, or indefinite maintenance.
    #[serde(default = "default_phase")]
    pub phase: String,
    /// Fixed maintenance reference, learned once or chosen explicitly.
    #[serde(default)]
    pub maintenance_reference_kg: Option<f64>,
    /// Percentage on either side of the maintenance reference.
    #[serde(default = "default_range")]
    pub maintenance_range_pct: f64,
    pub revision: i64,
    pub active: bool,
    pub started_at: DateTime<Utc>,
    pub pace_started_at: DateTime<Utc>,
    pub timezone: String,
    pub weekly_loss_kg: f64,
    pub reminder_enabled: bool,
    /// Calendar weekday: Sunday=1 through Saturday=7.
    pub reminder_weekday: i32,
    pub reminder_minute: i32,
    pub updated_at: DateTime<Utc>,
    pub finish_date: Option<NaiveDate>,
    pub daily_steps_goal: Option<i32>,
}
/// Optimistic update. Start dates are assigned by the server, never by the client.
#[derive(Debug, Deserialize)]
pub struct WeightGoalInput {
    pub phase: Option<String>,
    #[serde(default, deserialize_with = "optional_reference")]
    pub maintenance_reference_kg: Option<Option<f64>>,
    pub maintenance_range_pct: Option<f64>,
    /// Absent preserves the goal; null disables it.
    #[serde(default, deserialize_with = "optional_steps")]
    pub daily_steps_goal: Option<Option<i32>>,
    /// Absent preserves the date for older clients; explicit null removes it.
    #[serde(default, deserialize_with = "optional_date")]
    pub finish_date: Option<Option<NaiveDate>>,
    pub revision: i64,
    pub active: bool,
    pub timezone: String,
    pub weekly_loss_kg: f64,
    pub reminder_enabled: bool,
    pub reminder_weekday: i32,
    pub reminder_minute: i32,
}
fn default_phase() -> String {
    "cut".into()
}
fn default_range() -> f64 {
    1.0
}
fn optional_reference<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<Option<f64>>, D::Error> {
    Option::<f64>::deserialize(d).map(Some)
}
fn optional_date<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<Option<NaiveDate>>, D::Error> {
    Option::<NaiveDate>::deserialize(d).map(Some)
}
fn optional_steps<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<Option<i32>>, D::Error> {
    Option::<i32>::deserialize(d).map(Some)
}
/// One real observation per local day. No interpolation or synthetic zeroes.
#[derive(Debug, Clone, FromRow)]
pub struct WeightDay {
    pub day: NaiveDate,
    pub kg: f64,
}

impl PostgresStore {
    /// Returns the active phase, creating default maintenance or closing an expired phase.
    /// # Errors
    /// Unknown device or database failure.
    pub async fn weight_goal(&self, device: &str) -> StorageResult<Option<WeightGoal>> {
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)")
            .bind(device)
            .fetch_one(self.pool())
            .await
            .map_err(fail)?;
        if !exists {
            return Err(StorageError::CorrectionNotFound);
        }
        self.ensure_weight_phase(device).await?;
        sqlx::query_as("SELECT phase,maintenance_reference_kg,maintenance_range_pct,id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal FROM weight_goals WHERE device_id=$1").bind(device).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Saves atomically with a revision receipt. An identical retry is idempotent.
    /// # Errors
    /// Invalid settings, stale revision, unknown device, or database failure.
    pub async fn save_weight_goal(
        &self,
        device: &str,
        q: &WeightGoalInput,
    ) -> StorageResult<WeightGoal> {
        if q.revision < 0
            || !q.weekly_loss_kg.is_finite()
            || !(0.0..=1.0).contains(&q.weekly_loss_kg)
            || !(1..=7).contains(&q.reminder_weekday)
            || !(0..1440).contains(&q.reminder_minute)
        {
            return Err(StorageError::InvalidQuery(
                "Choose a valid weekly rate and reminder time.".into(),
            ));
        }
        if q.daily_steps_goal
            .flatten()
            .is_some_and(|steps| !(1..=100_000).contains(&steps))
        {
            return Err(StorageError::InvalidQuery(
                "Choose a daily step goal between 1 and 100,000.".into(),
            ));
        }
        self.progress_today(&q.timezone).await?;
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)")
            .bind(device)
            .fetch_one(self.pool())
            .await
            .map_err(fail)?;
        if !exists {
            return Err(StorageError::CorrectionNotFound);
        }
        let has_goal: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM weight_goals WHERE device_id=$1)")
                .bind(device)
                .fetch_one(self.pool())
                .await
                .map_err(fail)?;
        if has_goal {
            self.ensure_weight_phase(device).await?;
        }
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        let old: Option<WeightGoal> = sqlx::query_as("SELECT phase,maintenance_reference_kg,maintenance_range_pct,id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal FROM weight_goals WHERE device_id=$1 FOR UPDATE").bind(device).fetch_optional(&mut *tx).await.map_err(fail)?;
        if q.phase.is_none() && q.active && old.as_ref().is_some_and(|g| g.phase != "cut") {
            return Err(StorageError::CorrectionConflict(
                "Update the app before editing this goal phase.".into(),
            ));
        }
        let requested_phase = q.phase.as_deref().unwrap_or("cut");
        if !["cut", "bulk", "maintenance"].contains(&requested_phase) {
            return Err(StorageError::InvalidQuery(
                "Choose cut, bulk or maintenance.".into(),
            ));
        }
        let phase = if q.active {
            requested_phase
        } else {
            "maintenance"
        };
        let switching = old.as_ref().is_some_and(|g| g.phase != phase || !g.active);
        let reference = if phase == "maintenance" {
            q.maintenance_reference_kg.unwrap_or_else(|| {
                old.as_ref()
                    .filter(|g| g.phase == phase)
                    .and_then(|g| g.maintenance_reference_kg)
            })
        } else {
            None
        };
        let range = q.maintenance_range_pct.unwrap_or_else(|| {
            old.as_ref()
                .filter(|g| g.phase == phase)
                .map_or(1.0, |g| g.maintenance_range_pct)
        });
        if reference.is_some_and(|v| !v.is_finite() || !(20.0..=400.0).contains(&v))
            || !range.is_finite()
            || !(0.5..=5.0).contains(&range)
        {
            return Err(StorageError::InvalidQuery(
                "Choose a valid reference and a range between 0.5% and 5%.".into(),
            ));
        }
        let rate = if phase == "maintenance" {
            0.0
        } else {
            q.weekly_loss_kg
        };
        if phase != "maintenance" && !(0.05..=1.0).contains(&rate) {
            return Err(StorageError::InvalidQuery(
                "Choose a weekly rate between 0.05 and 1 kg.".into(),
            ));
        }
        let finish = if phase == "maintenance" {
            None
        } else {
            q.finish_date.unwrap_or_else(|| {
                old.as_ref()
                    .filter(|g| g.phase == phase)
                    .and_then(|g| g.finish_date)
            })
        };
        let steps = if !q.active {
            sqlx::query_scalar::<_, Option<i32>>("SELECT (settings->>'daily_steps_goal')::integer FROM weight_goal_history WHERE device_id=$1 AND settings->>'phase'='maintenance' ORDER BY ended_at DESC LIMIT 1").bind(device).fetch_optional(&mut *tx).await.map_err(fail)?.flatten()
        } else {
            q.daily_steps_goal.unwrap_or_else(|| {
                old.as_ref()
                    .filter(|g| g.phase == phase)
                    .and_then(|g| g.daily_steps_goal)
            })
        };
        if let Some(ref old) = old
            && old.daily_steps_goal == steps
            && old.finish_date == finish
            && old.active
            && old.phase == phase
            && old.maintenance_reference_kg == reference
            && old.maintenance_range_pct == range
            && old.timezone == q.timezone
            && old.weekly_loss_kg == rate
            && old.reminder_enabled == q.reminder_enabled
            && old.reminder_weekday == q.reminder_weekday
            && old.reminder_minute == q.reminder_minute
        {
            return Ok(old.clone());
        }
        if old.as_ref().map_or(0, |g| g.revision) != q.revision {
            return Err(StorageError::CorrectionConflict(
                "Your goal changed. Refresh before saving.".into(),
            ));
        }
        if old.is_none() && !q.active {
            return Err(StorageError::InvalidQuery(
                "Start a goal before ending it.".into(),
            ));
        }
        let now = Utc::now();
        let restart = old.is_none() || switching;
        if restart && q.phase.is_some() && phase != "maintenance" && finish.is_none() {
            return Err(StorageError::InvalidQuery(
                "Choose a finish date for this phase.".into(),
            ));
        }
        let new_pace = restart
            || old.as_ref().is_some_and(|g| {
                g.weekly_loss_kg != rate
                    || g.timezone != q.timezone
                    || g.maintenance_reference_kg != reference
                    || g.maintenance_range_pct != range
            });
        let start = if restart {
            now
        } else {
            old.as_ref().map_or(now, |g| g.started_at)
        };
        let pace = if new_pace {
            now
        } else {
            old.as_ref().map_or(now, |g| g.pace_started_at)
        };
        if let Some(end) = finish {
            let start_day = self.weight_local_day(start, &q.timezone).await?;
            let today = self.weight_local_day(now, &q.timezone).await?;
            let changed = restart || old.as_ref().and_then(|g| g.finish_date) != Some(end);
            if end <= start_day || (end - start_day).num_days() > 730 || (changed && end < today) {
                return Err(StorageError::InvalidQuery(
                    "Choose a finish date after the start, within two years, and not in the past."
                        .into(),
                ));
            }
        }
        let saved: WeightGoal=sqlx::query_as("INSERT INTO weight_goals(device_id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal,phase,maintenance_reference_kg,maintenance_range_pct) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) ON CONFLICT(device_id) DO UPDATE SET phase=EXCLUDED.phase,maintenance_reference_kg=EXCLUDED.maintenance_reference_kg,maintenance_range_pct=EXCLUDED.maintenance_range_pct,revision=EXCLUDED.revision,active=EXCLUDED.active,started_at=EXCLUDED.started_at,pace_started_at=EXCLUDED.pace_started_at,timezone=EXCLUDED.timezone,weekly_loss_kg=EXCLUDED.weekly_loss_kg,reminder_enabled=EXCLUDED.reminder_enabled,reminder_weekday=EXCLUDED.reminder_weekday,reminder_minute=EXCLUDED.reminder_minute,updated_at=EXCLUDED.updated_at,finish_date=EXCLUDED.finish_date,daily_steps_goal=EXCLUDED.daily_steps_goal RETURNING phase,maintenance_reference_kg,maintenance_range_pct,id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal")
            .bind(device).bind(q.revision+1).bind(true).bind(start).bind(pace).bind(&q.timezone).bind(rate).bind(q.reminder_enabled).bind(q.reminder_weekday).bind(q.reminder_minute).bind(now).bind(finish).bind(steps).bind(phase).bind(reference).bind(range).fetch_one(&mut *tx).await.map_err(fail)?;
        sqlx::query("INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w WHERE device_id=$1").bind(device).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(saved)
    }
    /// Resolves a timestamp into the goal's calendar. The zone is validated on save.
    /// # Errors
    /// Invalid zone or database failure.
    pub async fn weight_local_day(&self, at: DateTime<Utc>, tz: &str) -> StorageResult<NaiveDate> {
        sqlx::query_scalar("SELECT ($1::timestamptz AT TIME ZONE $2)::date")
            .bind(at)
            .bind(tz)
            .fetch_one(self.pool())
            .await
            .map_err(fail)
    }
    /// Fetches at most 112 daily observations, preferring Health then latest timestamp/id.
    /// # Errors
    /// Database failure.
    pub async fn weight_goal_days(
        &self,
        device: &str,
        tz: &str,
        now: DateTime<Utc>,
    ) -> StorageResult<Vec<WeightDay>> {
        sqlx::query_as("SELECT DISTINCT ON ((measured_at AT TIME ZONE $2)::date) (measured_at AT TIME ZONE $2)::date AS day,kg FROM weight_readings WHERE device_id=$1 AND NOT removed AND kg BETWEEN 20 AND 400 AND measured_at<=$3 AND measured_at>=((($3::timestamptz AT TIME ZONE $2)::date-112)::timestamp AT TIME ZONE $2) ORDER BY (measured_at AT TIME ZONE $2)::date, (source='health') DESC, measured_at DESC,id DESC")
            .bind(device).bind(tz).bind(now).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Canonical daily readings in a bounded calendar window, including old cut baselines.
    /// # Errors
    /// Database failure or an oversized window.
    pub async fn weight_days_between(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
        now: DateTime<Utc>,
    ) -> StorageResult<Vec<WeightDay>> {
        if to < from || (to - from).num_days() > 112 {
            return Err(StorageError::InvalidQuery("Invalid weight window.".into()));
        }
        sqlx::query_as("SELECT DISTINCT ON ((measured_at AT TIME ZONE $2)::date) (measured_at AT TIME ZONE $2)::date AS day,kg FROM weight_readings WHERE device_id=$1 AND NOT removed AND kg BETWEEN 20 AND 400 AND measured_at<=$5 AND measured_at>=($3::date::timestamp AT TIME ZONE $2) AND measured_at<(($4::date+1)::timestamp AT TIME ZONE $2) ORDER BY (measured_at AT TIME ZONE $2)::date, (source='health') DESC, measured_at DESC,id DESC")
            .bind(device).bind(tz).bind(from).bind(to).bind(now).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Canonical daily weigh-ins in the cut, including both boundary days.
    /// Unlike pace history, chart readings must survive cuts longer than 112 days and
    /// gaps in logging. One row per local day; source priority is unchanged.
    /// # Errors
    /// Database failure or invalid timezone.
    pub async fn cut_weight_days(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
        now: DateTime<Utc>,
    ) -> StorageResult<Vec<WeightDay>> {
        if to < from {
            return Ok(Vec::new());
        }
        sqlx::query_as(
            "WITH daily AS (
                SELECT DISTINCT ON ((measured_at AT TIME ZONE $2)::date)
                    (measured_at AT TIME ZONE $2)::date AS day, kg
                FROM weight_readings
                WHERE device_id=$1 AND NOT removed AND kg BETWEEN 20 AND 400
                    AND measured_at<=$5
                    AND measured_at>=($3::date::timestamp AT TIME ZONE $2)
                    AND measured_at<(($4::date+1)::timestamp AT TIME ZONE $2)
                ORDER BY (measured_at AT TIME ZONE $2)::date,
                    (source='health') DESC, measured_at DESC, id DESC
            )
            SELECT day,kg FROM daily
            ORDER BY day",
        )
        .bind(device)
        .bind(tz)
        .bind(from)
        .bind(to)
        .bind(now)
        .fetch_all(self.pool())
        .await
        .map_err(fail)
    }
}
