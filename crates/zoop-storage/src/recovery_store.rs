//! Retryable observation work, separate from sleep algorithm versions and GETs.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::NaiveDate;
use serde_json::Value;
use sqlx::{FromRow, PgConnection};

/// A bounded unit of observation work; failed claims become available again.
#[derive(Debug, FromRow)]
pub struct RecoveryJob {
    pub device_id: String,
    pub day: NaiveDate,
    pub tz: String,
    pub formula_version: i32,
    pub generation: i64,
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Recovery, e)
}
/// Enqueues the changed day and existing later nights that can use it as baseline.
/// Called inside the sleep publication transaction, including empty publications.
pub(crate) async fn invalidate(
    connection: &mut PgConnection,
    device: &str,
    day: NaiveDate,
    tz: &str,
) -> StorageResult<()> {
    sqlx::query(
        r#"
INSERT INTO recovery_jobs(device_id,day,tz,formula_version)
SELECT $1,d,$3,v FROM (
 SELECT $2::date d UNION SELECT (end_ts AT TIME ZONE $3)::date
 FROM sleep_sessions WHERE device_id=$1 AND status='active' AND kind='main'
 AND (end_ts AT TIME ZONE $3)::date BETWEEN $2 AND $2::date+28
) days CROSS JOIN (
 SELECT DISTINCT formula_version v FROM recovery_jobs WHERE device_id=$1
 UNION SELECT 1
) versions WHERE d<=(now() AT TIME ZONE $3)::date
ON CONFLICT(device_id,day,tz,formula_version) DO UPDATE
 SET generation=recovery_jobs.generation+1,available_at=now()
"#,
    )
    .bind(device)
    .bind(day)
    .bind(tz)
    .execute(connection)
    .await
    .map_err(fail)?;
    Ok(())
}
impl PostgresStore {
    /// Adds missing dates for the current formula without rescheduling completed work.
    /// # Errors
    /// Database failure; the next reconciliation retries safely.
    pub async fn seed_recovery(&self, version: i32) -> StorageResult<()> {
        sqlx::query(
            r#"
INSERT INTO recovery_jobs(device_id,day,tz,formula_version)
SELECT DISTINCT s.device_id,(s.end_ts AT TIME ZONE coalesce(p.tz,'UTC'))::date,
 coalesce(p.tz,'UTC'),$1 FROM sleep_sessions s LEFT JOIN profiles p ON p.device_id=s.device_id
WHERE s.status='active' AND s.kind='main' AND s.end_ts<=now()
ON CONFLICT DO NOTHING
"#,
        )
        .bind(version)
        .execute(self.pool())
        .await
        .map_err(fail)?;
        Ok(())
    }
    /// Claims one ready observation. An interrupted worker retries after 30 seconds.
    /// # Errors
    /// Database failure.
    pub async fn claim_recovery(&self, version: i32) -> StorageResult<Option<RecoveryJob>> {
        sqlx::query_as(
            r#"
WITH candidate AS (
 SELECT * FROM recovery_jobs WHERE formula_version=$1 AND generation>completed_generation
 AND available_at<=now() ORDER BY available_at,day DESC
 FOR UPDATE SKIP LOCKED LIMIT 1
) UPDATE recovery_jobs j SET available_at=now()+interval '30 seconds' FROM candidate c
WHERE (j.device_id,j.day,j.tz,j.formula_version)=(c.device_id,c.day,c.tz,c.formula_version)
RETURNING j.device_id,j.day,j.tz,j.formula_version,j.generation
"#,
        )
        .bind(version)
        .fetch_optional(self.pool())
        .await
        .map_err(fail)
    }
    /// Appends an immutable source/result pair and acknowledges only this generation.
    /// # Errors
    /// Database failure; observation and completion are one transaction.
    pub async fn record_recovery(
        &self,
        job: &RecoveryJob,
        fingerprint: &str,
        inputs: &Value,
        result: &Value,
    ) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        sqlx::query("INSERT INTO recovery_observations(device_id,day,tz,formula_version,input_fingerprint,inputs,result) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING")
            .bind(&job.device_id).bind(job.day).bind(&job.tz).bind(job.formula_version)
            .bind(fingerprint).bind(inputs).bind(result).execute(&mut *tx).await.map_err(fail)?;
        sqlx::query("UPDATE recovery_jobs SET completed_generation=greatest(completed_generation,$5) WHERE device_id=$1 AND day=$2 AND tz=$3 AND formula_version=$4")
            .bind(&job.device_id).bind(job.day).bind(&job.tz).bind(job.formula_version)
            .bind(job.generation).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)
    }
}
