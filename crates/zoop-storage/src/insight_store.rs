//! Bounded, read-only snapshots for morning comparisons. No derived values are persisted.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use serde_json::Value;
use sqlx::{FromRow, types::Json};
/// Effective main sleep plus measured recording coverage and wake evidence.
#[derive(Debug, FromRow)]
pub struct InsightNight {
    pub id: i64,
    pub revision: i64,
    pub day: NaiveDate,
    pub timezone: String,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub duration_s: i64,
    pub metrics: Json<Value>,
    pub pending: bool,
    pub complete: bool,
    pub hr_samples: i64,
    pub onset_minute: f64,
    pub wake_minute: f64,
}
/// All inputs share a repeatable-read snapshot, including outstanding analysis.
#[derive(Debug)]
pub struct InsightSnapshot {
    pub nights: Vec<InsightNight>,
    pub pending: bool,
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::MorningInsights, e)
}
impl PostgresStore {
    /// Reads at most one main sleep per day, in a caller-bounded calendar window.
    /// # Errors
    /// Database or timezone conversion failure.
    pub async fn insight_snapshot(
        &self,
        device: &str,
        from: NaiveDate,
        day: NaiveDate,
        tz: &str,
        sleep_version: i32,
    ) -> StorageResult<Option<InsightSnapshot>> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let valid_zone: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)")
                .bind(tz)
                .fetch_one(&mut *tx)
                .await
                .map_err(fail)?;
        if !valid_zone {
            return Err(StorageError::InvalidQuery(
                "Choose a valid time zone.".into(),
            ));
        }
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)")
            .bind(device)
            .fetch_one(&mut *tx)
            .await
            .map_err(fail)?;
        if !exists {
            return Ok(None);
        }
        let pending:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM analysis_jobs WHERE device_id=$1 AND kind='sleep' AND day=$2 AND algo_version=$3 AND generation>completed_generation)")
            .bind(device).bind(day).bind(sleep_version).fetch_one(&mut *tx).await.map_err(fail)?;
        let nights=sqlx::query_as::<_,InsightNight>(r#"
WITH ranked AS (
 SELECT s.*, (end_ts AT TIME ZONE $4)::date AS day,
 row_number() OVER (PARTITION BY (end_ts AT TIME ZONE $4)::date ORDER BY fixed DESC,duration_s DESC,id) AS rank
 FROM sleep_sessions s WHERE device_id=$1 AND status='active' AND kind='main'
 AND end_ts >= $2::date::timestamp AT TIME ZONE $4
 AND end_ts < ($3::date+1)::timestamp AT TIME ZONE $4
)
SELECT s.id,s.revision,s.day,s.timezone,s.start_ts,s.end_ts,s.duration_s,s.metrics,
 (s.metrics_pending OR EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=s.device_id AND j.kind='sleep' AND j.algo_version=$5 AND j.day=(s.end_ts AT TIME ZONE s.timezone)::date AND j.tz=s.timezone AND j.generation>j.completed_generation)) AS pending,
 (s.fixed OR ((SELECT count(*)>=270 AND count(*) FILTER(WHERE band_state<>2)>=150
 FROM samples WHERE device_id=$1 AND ts>=s.start_ts-interval '5 minutes' AND ts<s.start_ts)
 AND (SELECT count(*)>=1500 AND count(*) FILTER(WHERE band_state IN (0,3))>=1500
 FROM samples WHERE device_id=$1 AND ts>=s.end_ts AND ts<s.end_ts+interval '30 minutes'))) AND s.end_ts<=now() AS complete,
 (SELECT count(*) FROM samples WHERE device_id=$1 AND ts>=s.start_ts AND ts<s.end_ts AND hr IS NOT NULL) AS hr_samples,
 (extract(epoch FROM (s.start_ts AT TIME ZONE s.timezone)::time)/60)::float8 AS onset_minute,
 (extract(epoch FROM (s.end_ts AT TIME ZONE s.timezone)::time)/60)::float8 AS wake_minute
FROM ranked s WHERE rank=1 ORDER BY day
"#).bind(device).bind(from).bind(day).bind(tz).bind(sleep_version).fetch_all(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(Some(InsightSnapshot { nights, pending }))
    }
}
