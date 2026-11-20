//! Idempotent phase transitions and a maintenance reference that never follows drift.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::HealthSync, e)
}
impl PostgresStore {
    /// Ensures one active phase and learns its maintenance reference exactly once.
    /// # Errors
    /// Unknown device or database failure.
    pub async fn ensure_weight_phase(&self, device: &str) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        sqlx::query("WITH created AS (
            INSERT INTO weight_goals(device_id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,phase)
            SELECT $1,1,true,now(),now(),coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC'),0,false,1,1200,now(),'maintenance'
            ON CONFLICT(device_id) DO NOTHING RETURNING *
        ) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(created) FROM created")
        .bind(device).execute(&mut *tx).await.map_err(fail)?;
        sqlx::query("WITH expired AS (
            UPDATE weight_goals SET active=false,revision=revision+1,updated_at=((finish_date+1)::timestamp AT TIME ZONE timezone)
            WHERE device_id=$1 AND active AND finish_date IS NOT NULL AND ((finish_date+1)::timestamp AT TIME ZONE timezone)<=now() RETURNING *
        ) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(expired) FROM expired")
        .bind(device).execute(&mut *tx).await.map_err(fail)?;
        sqlx::query("WITH changed AS (
            UPDATE weight_goals w SET active=true,phase='maintenance',weekly_loss_kg=0,started_at=updated_at,pace_started_at=updated_at,
            finish_date=NULL,maintenance_reference_kg=NULL,maintenance_range_pct=1,revision=revision+1,
            daily_steps_goal=(SELECT (settings->>'daily_steps_goal')::integer FROM weight_goal_history WHERE device_id=$1 AND settings->>'phase'='maintenance' ORDER BY ended_at DESC LIMIT 1)
            WHERE device_id=$1 AND NOT active RETURNING *
        ) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(changed) FROM changed")
        .bind(device).execute(&mut *tx).await.map_err(fail)?;
        // Canonical daily weights, full calendar weeks, and a first eligible week.
        // Locking the phase prevents two readers choosing different references.
        sqlx::query("WITH g AS (SELECT * FROM weight_goals WHERE device_id=$1 AND phase='maintenance' AND maintenance_reference_kg IS NULL),
        daily AS (
          SELECT DISTINCT ON ((r.measured_at AT TIME ZONE g.timezone)::date)
           (r.measured_at AT TIME ZONE g.timezone)::date AS day,r.kg,g.pace_started_at,g.timezone
          FROM weight_readings r CROSS JOIN g WHERE r.device_id=$1 AND NOT r.removed AND r.kg BETWEEN 20 AND 400 AND r.measured_at<=now()
          AND r.measured_at>=g.pace_started_at ORDER BY (r.measured_at AT TIME ZONE g.timezone)::date,(r.source='health') DESC,r.measured_at DESC,r.id DESC
        ), weeks AS (
          SELECT date_trunc('week',day)::date AS week,percentile_cont(0.5) WITHIN GROUP(ORDER BY kg) AS kg
          FROM daily WHERE date_trunc('week',day)::date >= (pace_started_at AT TIME ZONE timezone)::date
           AND date_trunc('week',day)::date+7 <= (now() AT TIME ZONE timezone)::date
          GROUP BY date_trunc('week',day)::date HAVING count(*)>=4 AND max(day)-min(day)>=4
          ORDER BY week LIMIT 1
        ), changed AS (
          UPDATE weight_goals SET maintenance_reference_kg=weeks.kg,revision=revision+1 FROM weeks WHERE device_id=$1 RETURNING weight_goals.*
        ) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(changed) FROM changed")
        .bind(device).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)
    }
}
