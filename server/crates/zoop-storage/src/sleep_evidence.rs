//! Cached recording evidence. Changes and publication share the device lock.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use sqlx::PgConnection;

fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::MorningInsights, e)
}

/// Remove evidence when overnight context or wake-confirmation samples change.
/// A new sleep-labelled sample on the same date can also change the chosen main sleep.
pub(crate) async fn invalidate(
    tx: &mut PgConnection,
    device: &str,
    times: &[DateTime<Utc>],
) -> StorageResult<()> {
    sqlx::query("DELETE FROM sleep_evidence e USING sleep_sessions s WHERE e.session_id=s.id AND s.device_id=$1 AND EXISTS (
      SELECT 1 FROM unnest($2::timestamptz[]) at WHERE
      at>=s.start_ts-interval '24 hours' AND at<s.end_ts+interval '30 minutes'
      OR (at AT TIME ZONE s.timezone)::date=(s.end_ts AT TIME ZONE s.timezone)::date AND EXISTS
        (SELECT 1 FROM samples n WHERE n.device_id=$1 AND n.ts=at AND n.band_state=2))")
        .bind(device).bind(times).execute(tx).await.map_err(fail)?;
    Ok(())
}

impl PostgresStore {
    /// Warms missing evidence for settled nights only; GETs never populate it.
    /// Device locking prevents a concurrent decode from escaping invalidation.
    /// # Errors
    /// Database failure; the observation job remains retryable.
    pub async fn refresh_sleep_evidence(
        &self,
        device: &str,
        from: NaiveDate,
        to: NaiveDate,
        tz: &str,
        version: i32,
    ) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        sqlx::query(r#"
INSERT INTO sleep_evidence(session_id,revision,boundary_complete,hr_samples)
SELECT s.id,s.revision,
 ((SELECT count(*)>=270 AND count(*) FILTER(WHERE band_state<>2)>=150 FROM samples
   WHERE device_id=s.device_id AND ts>=s.start_ts-interval '5 minutes' AND ts<s.start_ts)
 AND (SELECT count(*)>=1500 AND count(*) FILTER(WHERE band_state IN (0,3))>=1500 FROM samples
   WHERE device_id=s.device_id AND ts>=s.end_ts AND ts<s.end_ts+interval '30 minutes')),
 (SELECT count(*) FROM samples WHERE device_id=s.device_id AND ts>=s.start_ts AND ts<s.end_ts AND hr IS NOT NULL)
FROM sleep_sessions s LEFT JOIN sleep_evidence e ON e.session_id=s.id AND e.revision=s.revision
WHERE s.device_id=$1 AND s.status='active' AND s.kind='main' AND NOT s.metrics_pending
AND s.end_ts >= $2::date::timestamp AT TIME ZONE $4 AND s.end_ts < ($3::date+1)::timestamp AT TIME ZONE $4
AND e.session_id IS NULL AND NOT EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='sleep'
 AND j.day=(s.end_ts AT TIME ZONE s.timezone)::date AND j.tz=s.timezone AND j.algo_version=$5 AND j.generation>j.completed_generation)
ON CONFLICT(session_id) DO UPDATE SET revision=EXCLUDED.revision,boundary_complete=EXCLUDED.boundary_complete,
 hr_samples=EXCLUDED.hr_samples,measured_at=now()
"#).bind(device).bind(from).bind(to).bind(tz).bind(version).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)
    }
}
