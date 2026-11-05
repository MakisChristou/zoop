//! Bounded activity inputs for progress. Reuses the invalidated daily projection.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::NaiveDate;
use sqlx::FromRow;

/// A local day, including absent recording and pending analysis.
#[derive(Debug, FromRow)]
pub struct ProgressDay {
    /// Local calendar date.
    pub day: NaiveDate,
    /// Observed seconds (one sample per second).
    pub samples: i64,
    /// Actual local day length, including daylight-saving changes.
    pub day_seconds: f64,
    /// Walking-filtered steps; missing stays absent.
    pub steps: Option<i64>,
    /// Seconds labelled walking/running by the strap.
    pub walking_s: Option<i64>,
    /// An effective resistance session starts on this day.
    pub strength: bool,
    /// Workout analysis or corrected metrics are outstanding.
    pub pending: bool,
}
impl PostgresStore {
    /// Validates an IANA zone before resolving today, returning a client error for invalid zones.
    /// # Errors
    /// Invalid timezone or database failure.
    pub async fn progress_today(&self, tz: &str) -> StorageResult<NaiveDate> {
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)")
                .bind(tz)
                .fetch_one(self.pool())
                .await
                .map_err(|e| StorageError::unavailable(StoreOperation::Progress, e))?;
        if !exists {
            return Err(StorageError::InvalidQuery(
                "Choose a valid time zone.".into(),
            ));
        }
        self.local_today(tz).await
    }

    /// Reads a bounded window, refreshing rebuildable daily summaries as necessary.
    /// # Errors
    /// Database or timezone failure.
    pub async fn progress_days(
        &self,
        device: &str,
        from: NaiveDate,
        until: NaiveDate,
        tz: &str,
    ) -> StorageResult<Vec<ProgressDay>> {
        sqlx::query_as(r#"
WITH dates AS (SELECT $2::date + n AS day FROM generate_series(0, ($3::date-$2::date)-1) n),
summaries AS MATERIALIZED (
 SELECT dates.day, s.samples, s.steps_walking, s.walking_s
 FROM dates CROSS JOIN LATERAL refresh_day_summary($1,$4,dates.day) s
)
SELECT d.day,d.samples, d.steps_walking AS steps,d.walking_s,
 extract(epoch FROM (((d.day+1)::timestamp AT TIME ZONE $4)-(d.day::timestamp AT TIME ZONE $4)))::float8 AS day_seconds,
 EXISTS(SELECT 1 FROM workout_sessions w WHERE w.device_id=$1 AND w.status='active' AND w.kind='resistance'
 AND w.start_ts>=d.day::timestamp AT TIME ZONE $4 AND w.start_ts<(d.day+1)::timestamp AT TIME ZONE $4) AS strength,
 (EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='workout' AND j.day=d.day AND j.tz=$4 AND j.generation>j.completed_generation)
 OR EXISTS(SELECT 1 FROM workout_sessions w WHERE w.device_id=$1 AND w.status='active' AND w.metrics_pending
 AND w.start_ts<(d.day+1)::timestamp AT TIME ZONE $4 AND w.end_ts>d.day::timestamp AT TIME ZONE $4)) AS pending
FROM summaries d ORDER BY d.day
"#).bind(device).bind(from).bind(until).bind(tz).fetch_all(self.pool()).await
        .map_err(|e| StorageError::unavailable(StoreOperation::Progress, e))
    }
}
