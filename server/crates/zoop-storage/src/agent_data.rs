//! Narrow, bounded agent projections. Exclude identities and free-form edit notes.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation, WeightGoal};
use chrono::NaiveDate;
use serde_json::Value;
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::AgentAccess, e)
}
impl PostgresStore {
    /// Effective sessions, with physiology excluded from the sleep scope.
    /// # Errors
    /// Database failure or an oversized result.
    pub async fn agent_sessions(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
        sleep: bool,
    ) -> StorageResult<Vec<Value>> {
        let (table, day, metrics) = if sleep {
            (
                "sleep_sessions",
                "end_ts",
                "jsonb_build_object('window',metrics #> '{sleep,window}','stages',metrics #> '{sleep,stages}')",
            )
        } else {
            (
                "workout_sessions",
                "start_ts",
                "jsonb_build_object('load',metrics->'load','avg_hr_bpm',metrics->'avg_hr','zones_min',metrics->'zones_min')",
            )
        };
        let query = format!(
            "SELECT jsonb_build_object('day',({day} AT TIME ZONE $2)::date,'start',start_ts,'end',end_ts,'duration_s',duration_s,'kind',kind,'edited',edited,'pending',metrics_pending,'metrics',CASE WHEN metrics_pending THEN NULL ELSE {metrics} END) FROM {table} WHERE device_id=$1 AND status='active' AND {day}>=$3::date::timestamp AT TIME ZONE $2 AND {day}<($4::date+1)::timestamp AT TIME ZONE $2 AND end_ts<=now() ORDER BY {day},id LIMIT 2001"
        );
        let rows: Vec<Value> = sqlx::query_scalar(&query)
            .bind(device)
            .bind(tz)
            .bind(from)
            .bind(to)
            .fetch_all(self.pool())
            .await
            .map_err(fail)?;
        if rows.len() > 2000 {
            return Err(StorageError::InvalidQuery(
                "Choose a shorter period.".into(),
            ));
        }
        Ok(rows)
    }
    /// Recorded weights with source type, excluding external identifiers and names.
    /// # Errors
    /// Database failure or oversized result.
    pub async fn agent_weights(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<Vec<Value>> {
        let rows:Vec<Value>=sqlx::query_scalar("SELECT jsonb_build_object('day',(measured_at AT TIME ZONE $2)::date,'measured_at',measured_at,'kg',kg,'source',source) FROM weight_readings WHERE device_id=$1 AND NOT removed AND measured_at>=$3::date::timestamp AT TIME ZONE $2 AND measured_at<($4::date+1)::timestamp AT TIME ZONE $2 AND measured_at<=now() ORDER BY measured_at,id LIMIT 2001")
            .bind(device).bind(tz).bind(from).bind(to).fetch_all(self.pool()).await.map_err(fail)?;
        if rows.len() > 2000 {
            return Err(StorageError::InvalidQuery(
                "Choose a shorter period.".into(),
            ));
        }
        Ok(rows)
    }
    /// Current saved plan without initiating goal rollover or other health writes.
    /// # Errors
    /// Database failure.
    pub async fn agent_goal(&self, device: &str) -> StorageResult<Option<WeightGoal>> {
        sqlx::query_as("SELECT phase,maintenance_reference_kg,maintenance_range_pct,id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal FROM weight_goals WHERE device_id=$1")
            .bind(device).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Completed plans fully within the allowed window; no implicit historical disclosure.
    /// # Errors
    /// Database failure.
    pub async fn agent_goal_history(
        &self,
        device: &str,
        tz: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<Vec<Value>> {
        let rows: Vec<Value> = sqlx::query_scalar("SELECT jsonb_build_object('phase',settings->'phase','started_at',settings->'started_at','ended_at',ended_at,'finish_date',settings->'finish_date','weekly_loss_kg',settings->'weekly_loss_kg','daily_steps_goal',settings->'daily_steps_goal','target_weight_kg',target_weight_kg) FROM weight_goal_history WHERE device_id=$1 AND started_at>=$3::date::timestamp AT TIME ZONE $2 AND ended_at<($4::date+1)::timestamp AT TIME ZONE $2 ORDER BY started_at LIMIT 101")
            .bind(device).bind(tz).bind(from).bind(to).fetch_all(self.pool()).await.map_err(fail)?;
        if rows.len() > 100 {
            return Err(StorageError::InvalidQuery(
                "Choose a shorter period.".into(),
            ));
        }
        Ok(rows)
    }
}
