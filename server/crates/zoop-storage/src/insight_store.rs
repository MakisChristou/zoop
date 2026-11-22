//! Bounded read-only snapshots reuse worker-published recording evidence.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use serde_json::Value;
use sqlx::{FromRow, types::Json};
/// Effective main sleep plus measured recording coverage and wake evidence.
#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct InsightNight {
    pub id: i64,
    pub revision: i64,
    pub day_count: i64,
    pub day: NaiveDate,
    pub timezone: String,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub duration_s: i64,
    pub metrics: Json<Value>,
    /// Pending work on this calendar day, matching the private insights gate.
    pub day_pending: bool,
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
        let nights = sqlx::query_as::<_, InsightNight>(include_str!("insight_snapshot.sql"))
            .bind(device)
            .bind(from)
            .bind(day)
            .bind(tz)
            .bind(sleep_version)
            .fetch_all(&mut *tx)
            .await
            .map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        let pending = nights
            .iter()
            .find(|n| n.day == day)
            .map_or(pending, |n| n.pending || n.day_pending);
        Ok(Some(InsightSnapshot { nights, pending }))
    }
}
