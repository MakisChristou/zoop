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
}
/// Optimistic update. Start dates are assigned by the server, never by the client.
#[derive(Debug, Deserialize)]
pub struct WeightGoalInput {
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
fn optional_date<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<Option<NaiveDate>>, D::Error> {
    Option::<NaiveDate>::deserialize(d).map(Some)
}
/// One real observation per local day. No interpolation or synthetic zeroes.
#[derive(Debug, Clone, FromRow)]
pub struct WeightDay {
    pub day: NaiveDate,
    pub kg: f64,
}

impl PostgresStore {
    /// Returns settings, including paused goals, without creating one.
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
        sqlx::query_as("SELECT revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date FROM weight_goals WHERE device_id=$1").bind(device).fetch_optional(self.pool()).await.map_err(fail)
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
            || !(0.1..=1.0).contains(&q.weekly_loss_kg)
            || !(1..=7).contains(&q.reminder_weekday)
            || !(0..1440).contains(&q.reminder_minute)
        {
            return Err(StorageError::InvalidQuery(
                "Choose a weekly loss between 0.1 and 1 kg and a valid reminder time.".into(),
            ));
        }
        self.progress_today(&q.timezone).await?;
        self.weight_goal(device).await?;
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        let old: Option<WeightGoal> = sqlx::query_as("SELECT revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date FROM weight_goals WHERE device_id=$1 FOR UPDATE").bind(device).fetch_optional(&mut *tx).await.map_err(fail)?;
        let finish = q
            .finish_date
            .unwrap_or_else(|| old.as_ref().and_then(|g| g.finish_date));
        if let Some(ref old) = old
            && old.finish_date == finish
            && old.active == q.active
            && old.timezone == q.timezone
            && old.weekly_loss_kg == q.weekly_loss_kg
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
        let now = Utc::now();
        let restart = old.as_ref().is_none_or(|g| !g.active && q.active);
        let new_pace = restart
            || old
                .as_ref()
                .is_some_and(|g| g.weekly_loss_kg != q.weekly_loss_kg || g.timezone != q.timezone);
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
        let saved: WeightGoal=sqlx::query_as("INSERT INTO weight_goals(device_id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT(device_id) DO UPDATE SET revision=EXCLUDED.revision,active=EXCLUDED.active,started_at=EXCLUDED.started_at,pace_started_at=EXCLUDED.pace_started_at,timezone=EXCLUDED.timezone,weekly_loss_kg=EXCLUDED.weekly_loss_kg,reminder_enabled=EXCLUDED.reminder_enabled,reminder_weekday=EXCLUDED.reminder_weekday,reminder_minute=EXCLUDED.reminder_minute,updated_at=EXCLUDED.updated_at,finish_date=EXCLUDED.finish_date RETURNING revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date")
            .bind(device).bind(q.revision+1).bind(q.active).bind(start).bind(pace).bind(&q.timezone).bind(q.weekly_loss_kg).bind(q.reminder_enabled).bind(q.reminder_weekday).bind(q.reminder_minute).bind(now).bind(finish).fetch_one(&mut *tx).await.map_err(fail)?;
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
}
