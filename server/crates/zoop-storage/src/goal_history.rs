//! Immutable goal plans and bounded, source-preserving historical periods.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation, WeightGoal};
use chrono::{DateTime, Utc};
use sqlx::{FromRow, types::Json};

fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::HealthSync, e)
}

/// A closed cut. Measurements remain in their source table, never copied or deleted.
#[derive(Debug, FromRow)]
pub struct GoalPeriod {
    /// Stable goal identity.
    pub id: i64,
    /// Actual exclusive end of the period.
    pub ended_at: DateTime<Utc>,
    /// Manual, scheduled or incompletely reconstructed legacy closure.
    pub end_reason: String,
    /// Last active plan, including original intended finish and pace.
    pub settings: Json<WeightGoal>,
    /// Intended target frozen at closure; absent if no baseline was known.
    pub target_weight_kg: Option<f64>,
}
impl PostgresStore {
    /// Closes a scheduled cut once at midnight after its final local day.
    /// The archive, current state and audit receipt are committed atomically.
    /// # Errors
    /// Database failure.
    pub async fn expire_weight_goal(&self, device: &str) -> StorageResult<()> {
        sqlx::query("WITH expired AS (
            UPDATE weight_goals SET active=false,revision=revision+1,
                updated_at=((finish_date+1)::timestamp AT TIME ZONE timezone)
            WHERE device_id=$1 AND active AND finish_date IS NOT NULL
                AND ((finish_date+1)::timestamp AT TIME ZONE timezone)<=now()
            RETURNING *
        ) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(expired) FROM expired")
            .bind(device).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Lists closed cuts, newest first. Cursor ownership is checked before use.
    /// # Errors
    /// Missing device/cursor, invalid limit or database failure.
    pub async fn goal_history(
        &self,
        device: &str,
        before: Option<i64>,
        limit: i64,
    ) -> StorageResult<Vec<GoalPeriod>> {
        self.weight_goal(device).await?;
        if !(1..=51).contains(&limit) {
            return Err(StorageError::InvalidQuery("Invalid history limit.".into()));
        }
        if let Some(id) = before {
            self.goal_period(device, id).await?;
        }
        sqlx::query_as(
            "SELECT id,ended_at,end_reason,settings,target_weight_kg
            FROM weight_goal_history WHERE device_id=$1
            AND ($2::bigint IS NULL OR (started_at,id) < (
                SELECT started_at,id FROM weight_goal_history WHERE device_id=$1 AND id=$2))
            ORDER BY started_at DESC,id DESC LIMIT $3",
        )
        .bind(device)
        .bind(before)
        .bind(limit)
        .fetch_all(self.pool())
        .await
        .map_err(fail)
    }
    /// Reads one archived plan within the authenticated device dataset.
    /// # Errors
    /// Missing period or database failure.
    pub async fn goal_period(&self, device: &str, id: i64) -> StorageResult<GoalPeriod> {
        sqlx::query_as(
            "SELECT id,ended_at,end_reason,settings,target_weight_kg
            FROM weight_goal_history WHERE device_id=$1 AND id=$2",
        )
        .bind(device)
        .bind(id)
        .fetch_optional(self.pool())
        .await
        .map_err(fail)?
        .ok_or(StorageError::CorrectionNotFound)
    }
}
