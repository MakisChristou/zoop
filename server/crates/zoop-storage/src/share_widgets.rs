//! Narrow projections for the public versions of existing training cards.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::NaiveDate;
use serde_json::Value;
const MAX_ACTIVITIES: i64 = 10_000;
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Sharing, e)
}
fn bounds(from: NaiveDate, to: NaiveDate) -> StorageResult<()> {
    if to < from || (to - from).num_days() > 365 {
        return Err(StorageError::InvalidQuery("Invalid history window.".into()));
    }
    Ok(())
}
impl PostgresStore {
    /// Public timeline rows: dates, type, duration and load only. No stable private IDs.
    /// # Errors
    /// Database failure or a range too large to return without truncation.
    pub async fn shared_activities(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<Vec<Value>> {
        bounds(from, to)?;
        let rows = sqlx::query_scalar(
            r#"
            SELECT jsonb_build_object(
                'day',(start_ts AT TIME ZONE $2)::date,
                'kind',kind,
                'duration_s',duration_s,
                'load',metrics->'load')
            FROM workout_sessions
            WHERE device_id=$1
              AND status='active'
              AND NOT metrics_pending
              AND end_ts<=now()
              AND start_ts >= $3::date::timestamp AT TIME ZONE $2
              AND start_ts < ($4::date+1)::timestamp AT TIME ZONE $2
            ORDER BY start_ts DESC,id DESC
            LIMIT $5"#,
        )
        .bind(device)
        .bind(tz)
        .bind(from)
        .bind(to)
        .bind(MAX_ACTIVITIES + 1)
        .fetch_all(self.pool())
        .await
        .map_err(fail)?;
        if rows.len() as i64 > MAX_ACTIVITIES {
            return Err(StorageError::InvalidQuery(
                "Choose a shorter period for recent activities.".into(),
            ));
        }
        Ok(rows)
    }
    /// Heatmap tooltip summaries disclose only per-day types, durations and counts.
    /// # Errors
    /// Database failure or invalid date range.
    pub async fn shared_activity_days(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<Vec<Value>> {
        bounds(from, to)?;
        sqlx::query_scalar(
            r#"
            SELECT jsonb_build_object(
                'day',(start_ts AT TIME ZONE $2)::date,
                'kind',kind,
                'duration_s',sum(duration_s),
                'count',count(*))
            FROM workout_sessions
            WHERE device_id=$1
              AND status='active'
              AND NOT metrics_pending
              AND end_ts<=now()
              AND start_ts >= $3::date::timestamp AT TIME ZONE $2
              AND start_ts < ($4::date+1)::timestamp AT TIME ZONE $2
            GROUP BY (start_ts AT TIME ZONE $2)::date,kind
            ORDER BY (start_ts AT TIME ZONE $2)::date,kind"#,
        )
        .bind(device)
        .bind(tz)
        .bind(from)
        .bind(to)
        .fetch_all(self.pool())
        .await
        .map_err(fail)
    }
    /// Sport totals disclose no session dates, load or physiological measurements.
    /// # Errors
    /// Database failure or invalid date range.
    pub async fn shared_sports(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<Vec<Value>> {
        bounds(from, to)?;
        sqlx::query_scalar(
            r#"
            SELECT jsonb_build_object('kind',kind,
                'seconds',sum(duration_s),
                'count',count(*))
            FROM workout_sessions
            WHERE device_id=$1
              AND status='active'
              AND NOT metrics_pending
              AND end_ts<=now()
              AND start_ts >= $3::date::timestamp AT TIME ZONE $2
              AND start_ts < ($4::date+1)::timestamp AT TIME ZONE $2
            GROUP BY kind
            ORDER BY sum(duration_s) DESC,kind"#,
        )
        .bind(device)
        .bind(tz)
        .bind(from)
        .bind(to)
        .fetch_all(self.pool())
        .await
        .map_err(fail)
    }
}
