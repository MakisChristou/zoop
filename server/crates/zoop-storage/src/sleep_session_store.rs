//! Atomic sleep projection publication and downstream invalidation.
use crate::{AnalysisJob, PostgresStore, SessionCalculation, SessionDomain, StorageResult};
use crate::{
    analysis_store::{complete, fence},
    session_store::{fail, lock_device, publish_domain_sessions},
};
use chrono::{DateTime, Utc};
use serde_json::{Value, json};
impl PostgresStore {
    /// Publishes one wake-up date, including an empty result, without blanking other history.
    /// # Errors
    /// Storage failure; a stale worker is discarded without changes.
    pub async fn publish_sleep_sessions(
        &self,
        job: &AnalysisJob,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        sessions: &[SessionCalculation],
        workout_version: i32,
    ) -> StorageResult<bool> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        lock_device(&mut tx, &job.device_id).await?;
        if !fence(&mut tx, job).await? {
            tx.commit().await.map_err(fail)?;
            return Ok(false);
        }
        let before:Value=sqlx::query_scalar("SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM sleep_sessions s WHERE device_id=$1 AND status='active' AND end_ts >=$2 AND end_ts<$3")
    .bind(&job.device_id).bind(from).bind(to).fetch_one(&mut *tx).await.map_err(fail)?;
        publish_domain_sessions(&mut tx, SessionDomain::Sleep, job, from, to, sessions).await?;
        // One automatic main per saved wake-up date, with an explicit main taking priority.
        sqlx::query("WITH ranked AS(SELECT id,row_number() OVER(PARTITION BY (end_ts AT TIME ZONE timezone)::date ORDER BY (fixed AND kind='main') DESC,duration_s DESC,id) n FROM sleep_sessions WHERE device_id=$1 AND status='active' AND (NOT fixed OR kind='main')) UPDATE sleep_sessions s SET revision=revision+1,kind=CASE WHEN r.n=1 THEN 'main' ELSE 'nap' END FROM ranked r WHERE s.id=r.id AND NOT s.fixed AND s.kind<>CASE WHEN r.n=1 THEN 'main' ELSE 'nap' END")
   .bind(&job.device_id).execute(&mut *tx).await.map_err(fail)?;
        let after:Value=sqlx::query_scalar("SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM sleep_sessions s WHERE device_id=$1 AND status='active' AND end_ts >=$2 AND end_ts<$3")
    .bind(&job.device_id).bind(from).bind(to).fetch_one(&mut *tx).await.map_err(fail)?;
        // Keep a versioned day projection for compatibility and analysis provenance.
        sqlx::query("INSERT INTO sleeps(device_id,night_of,algo_version,start_ts,end_ts,stages,metrics) SELECT device_id,night_of,$3,start_ts,end_ts,stages,metrics FROM effective_sleep_read r WHERE device_id=$1 AND night_of=$2 AND EXISTS(SELECT 1 FROM effective_sleep_sessions s WHERE s.device_id=r.device_id AND s.wake_day=r.night_of AND s.kind='main') ON CONFLICT(device_id,night_of,algo_version) DO UPDATE SET start_ts=EXCLUDED.start_ts,end_ts=EXCLUDED.end_ts,stages=EXCLUDED.stages,metrics=EXCLUDED.metrics")
    .bind(&job.device_id).bind(job.day).bind(job.algo_version).execute(&mut *tx).await.map_err(fail)?;
        sqlx::query("DELETE FROM sleeps r WHERE device_id=$1 AND night_of=$2 AND algo_version=$3 AND NOT EXISTS(SELECT 1 FROM effective_sleep_sessions s WHERE s.device_id=r.device_id AND s.wake_day=r.night_of AND s.kind='main')")
    .bind(&job.device_id).bind(job.day).bind(job.algo_version).execute(&mut *tx).await.map_err(fail)?;
        if before != after {
            crate::session_store::invalidate(
                &mut tx,
                SessionDomain::Workout,
                &job.device_id,
                from - chrono::Duration::days(1),
                to,
                &job.tz,
                workout_version,
            )
            .await?;
            // RHR can be an input for later days until another valid night supersedes it.
            sqlx::query("UPDATE analysis_jobs SET generation=generation+1,available_at=least(available_at,now()),backfill=true WHERE device_id=$1 AND kind='workout' AND algo_version=$3 AND day >=$2")
    .bind(&job.device_id).bind(job.day).bind(workout_version).execute(&mut *tx).await.map_err(fail)?;
        }
        complete(&mut tx,job,json!({"sleep_version":job.algo_version,"timezone":job.tz,"window":"full local wake-up day"})).await?;
        crate::recovery_store::invalidate(&mut tx, &job.device_id, job.day, &job.tz).await?;
        tx.commit().await.map_err(fail)?;
        Ok(true)
    }
}
