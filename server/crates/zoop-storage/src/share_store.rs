//! Account-scoped sharing records and deliberately narrow public projections.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use serde_json::Value;
use sqlx::FromRow;

/// Sensitive sharing record. Debug deliberately omits credentials and configuration.
#[derive(FromRow)]
pub struct SharedDashboard {
    pub id: i64,
    pub account_id: i64,
    pub device_id: String,
    pub token: String,
    pub config: Value,
    pub password_hash: Option<String>,
    pub enabled: bool,
    pub expires_at: Option<DateTime<Utc>>,
    pub revision: i64,
}
impl std::fmt::Debug for SharedDashboard {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SharedDashboard")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Sharing, e)
}
impl PostgresStore {
    /// Lists only the authenticated owner's shares, including disabled ones.
    /// # Errors
    /// Database failure.
    pub async fn shared_dashboards(&self, owner: i64) -> StorageResult<Vec<SharedDashboard>> {
        sqlx::query_as("SELECT id,account_id,device_id,token,config,password_hash,enabled,expires_at,revision FROM shared_dashboards WHERE account_id=$1 ORDER BY id DESC")
   .bind(owner).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Resolves an active capability only while its owner is enabled and still owns the device.
    /// # Errors
    /// Database failure.
    pub async fn public_dashboard(&self, hash: &str) -> StorageResult<Option<SharedDashboard>> {
        sqlx::query_as("SELECT s.id,s.account_id,s.device_id,s.token,s.config,s.password_hash,s.enabled,s.expires_at,s.revision FROM shared_dashboards s JOIN accounts a ON a.id=s.account_id AND a.enabled JOIN device_owners o ON o.device_id=s.device_id AND o.account_id=s.account_id WHERE s.token_hash=$1 AND s.enabled AND (s.expires_at IS NULL OR s.expires_at>now())")
   .bind(hash).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Creates a share only for an owned device, with a per-account bound.
    /// # Errors
    /// Database failure, missing ownership, or share limit.
    pub async fn create_dashboard(&self, row: &SharedDashboard, hash: &str) -> StorageResult<i64> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        sqlx::query("SELECT id FROM accounts WHERE id=$1 FOR UPDATE")
            .bind(row.account_id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let id:Option<i64>=sqlx::query_scalar("INSERT INTO shared_dashboards(account_id,device_id,token_hash,token,config,password_hash,enabled,expires_at) SELECT $1,$2,$3,$4,$5,$6,$7,$8 WHERE EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$2) AND (SELECT count(*) FROM shared_dashboards WHERE account_id=$1)<50 RETURNING id")
   .bind(row.account_id).bind(&row.device_id).bind(hash).bind(&row.token).bind(&row.config).bind(&row.password_hash).bind(row.enabled).bind(row.expires_at).fetch_optional(&mut *tx).await.map_err(fail)?;
        let id = id.ok_or_else(|| {
            StorageError::InvalidQuery(
                "Cannot create this share. Check device ownership or remove an old share.".into(),
            )
        })?;
        tx.commit().await.map_err(fail)?;
        Ok(id)
    }
    /// Optimistic owner-only update; the link cannot silently switch to another device.
    /// # Errors
    /// Database failure.
    pub async fn update_dashboard(&self, row: &SharedDashboard) -> StorageResult<bool> {
        let r=sqlx::query("UPDATE shared_dashboards SET config=$4,password_hash=$5,enabled=$6,expires_at=$7,revision=revision+1 WHERE account_id=$1 AND id=$2 AND revision=$3 AND device_id=$8 AND EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$8)")
   .bind(row.account_id).bind(row.id).bind(row.revision).bind(&row.config).bind(&row.password_hash).bind(row.enabled).bind(row.expires_at).bind(&row.device_id).execute(self.pool()).await.map_err(fail)?;
        Ok(r.rows_affected() == 1)
    }
    /// Removes the link without touching any measurements.
    /// # Errors
    /// Database failure.
    pub async fn delete_dashboard(&self, owner: i64, id: i64) -> StorageResult<bool> {
        Ok(
            sqlx::query("DELETE FROM shared_dashboards WHERE account_id=$1 AND id=$2")
                .bind(owner)
                .bind(id)
                .execute(self.pool())
                .await
                .map_err(fail)?
                .rows_affected()
                == 1,
        )
    }
    /// Earliest date for selected categories only; no unselected-history metadata leaks.
    /// # Errors
    /// Database failure.
    pub async fn shared_earliest(
        &self,
        device: &str,
        tz: &str,
        keys: &[String],
    ) -> StorageResult<Option<NaiveDate>> {
        sqlx::query_scalar(r#"SELECT min(day) FROM (
 SELECT min((end_ts AT TIME ZONE $2)::date) AS day FROM sleep_sessions WHERE device_id=$1 AND status='active' AND kind='main' AND $3::text[] && ARRAY['sleep','hrv','resting_hr','recovery','daily_rings','sleep_timeline','sleep_stages','nightly_metrics','morning_outlook']
 UNION ALL SELECT min((ts AT TIME ZONE $2)::date) FROM (SELECT ts FROM samples WHERE device_id=$1 AND 'steps'=ANY($3) ORDER BY ts LIMIT 1) first_sample
 UNION ALL SELECT min(day) FROM strains WHERE device_id=$1 AND $3::text[] && ARRAY['load','activity_heatmap','daily_rings']
 UNION ALL SELECT min((start_ts AT TIME ZONE $2)::date) FROM workout_sessions WHERE device_id=$1 AND status='active' AND $3::text[] && ARRAY['workouts','activity_heatmap','recent_workouts','by_sport']
 UNION ALL SELECT min((measured_at AT TIME ZONE $2)::date) FROM weight_readings WHERE device_id=$1 AND NOT removed AND $3::text[] && ARRAY['weight','goal_progress','goal_weight']) dates"#)
   .bind(device).bind(tz).bind(keys).fetch_one(self.pool()).await.map_err(fail)
    }
    /// Public daily projections. Queries emit only the requested scalar, never raw metric bundles.
    /// # Errors
    /// Database failure or unsupported metric.
    pub async fn shared_points(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
        key: &str,
        version: i32,
    ) -> StorageResult<Vec<Value>> {
        if to < from || (to - from).num_days() > 365 {
            return Err(StorageError::InvalidQuery("Invalid history window.".into()));
        }
        if matches!(key, "sleep" | "hrv" | "resting_hr") {
            // Reuse the rings' exact effective-night query, but project the scalar
            // inside Postgres. A year of chart points must not transfer full nightly
            // stage bundles or evaluate unused physiology coverage to the API.
            let sql = format!(
                "SELECT jsonb_build_object('day', day, 'value', CASE WHEN pending OR day_pending THEN NULL ELSE CASE $6::text WHEN 'sleep' THEN metrics #> '{{sleep,window,asleep_s}}' WHEN 'hrv' THEN metrics #> '{{sleep,physiology,hrv_rmssd_ms}}' ELSE metrics #> '{{sleep,physiology,resting_hr}}' END END) FROM ({}) nights WHERE end_ts<=now() ORDER BY day",
                include_str!("insight_snapshot.sql")
            );
            return sqlx::query_scalar(&sql)
                .bind(device)
                .bind(from)
                .bind(to)
                .bind(tz)
                .bind(version)
                .bind(key)
                .fetch_all(self.pool())
                .await
                .map_err(fail);
        }
        let sql = match key {
            "steps" => {
                r#"SELECT jsonb_build_object('day',d.day,'value',CASE WHEN d.samples>0 THEN d.steps_walking END) FROM generate_series($3::date::timestamp,$4::date::timestamp,interval '1 day') g CROSS JOIN LATERAL refresh_day_summary($1,$2,g::date) d WHERE $5='steps' ORDER BY d.day"#
            }
            "load" => {
                r#"SELECT jsonb_build_object('day',day,'value',load) FROM strains s WHERE device_id=$1 AND day BETWEEN $3 AND $4 AND algo_version=coalesce((SELECT max(j.algo_version) FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='workout' AND j.day=s.day AND j.tz=$2 AND j.completed_generation>0 AND j.algo_version<=$6),1) AND $5='load' ORDER BY day"#
            }
            "weight" => {
                r#"SELECT jsonb_build_object('day',day,'value',kg) FROM (SELECT DISTINCT ON((measured_at AT TIME ZONE $2)::date) (measured_at AT TIME ZONE $2)::date AS day,kg FROM weight_readings WHERE device_id=$1 AND NOT removed AND measured_at<=now() AND measured_at>=$3::date::timestamp AT TIME ZONE $2 AND measured_at<($4::date+1)::timestamp AT TIME ZONE $2 ORDER BY (measured_at AT TIME ZONE $2)::date,(source='health') DESC,measured_at DESC,id DESC) w WHERE $5='weight' ORDER BY day"#
            }
            "workouts" => {
                r#"SELECT jsonb_build_object('day',(start_ts AT TIME ZONE $2)::date,'value',count(*)) FROM workout_sessions WHERE device_id=$1 AND status='active' AND NOT metrics_pending AND start_ts>=$3::date::timestamp AT TIME ZONE $2 AND start_ts<($4::date+1)::timestamp AT TIME ZONE $2 AND end_ts<=now() AND $5='workouts' GROUP BY (start_ts AT TIME ZONE $2)::date ORDER BY (start_ts AT TIME ZONE $2)::date"#
            }
            _ => return Err(StorageError::InvalidQuery("Unknown widget.".into())),
        };
        // The common binds keep data identifiers parameterized; only static SQL is selected.
        let query = sqlx::query_scalar(sql)
            .bind(device)
            .bind(tz)
            .bind(from)
            .bind(to)
            .bind(key);
        if key == "load" {
            query
                .bind(version)
                .fetch_all(self.pool())
                .await
                .map_err(fail)
        } else {
            query.fetch_all(self.pool()).await.map_err(fail)
        }
    }
}
