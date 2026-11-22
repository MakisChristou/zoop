//! Personal sleep display target. Independent of physiology and analysis jobs.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

/// Default display target until the owner saves or migrates a personal target.
pub const DEFAULT_SLEEP_GOAL_MINUTES: i32 = 480;

/// Authoritative display target and whether an explicit value has been saved.
#[derive(Debug, serde::Serialize)]
pub struct SleepGoal {
    pub minutes: i32,
    pub configured: bool,
}
impl PostgresStore {
    /// Read the owner's target, with the server default for an unset profile.
    /// # Errors
    /// Returns a storage error if the database cannot be read.
    pub async fn sleep_goal(&self, device: &str) -> StorageResult<SleepGoal> {
        let minutes: Option<i32> = sqlx::query_scalar::<_, Option<i32>>(
            "SELECT sleep_goal_minutes FROM profiles WHERE device_id=$1",
        )
        .bind(device)
        .fetch_optional(self.pool())
        .await
        .map_err(|e| StorageError::unavailable(StoreOperation::GetProfile, e))?
        .flatten();
        Ok(SleepGoal {
            minutes: minutes.unwrap_or(DEFAULT_SLEEP_GOAL_MINUTES),
            configured: minutes.is_some(),
        })
    }

    /// Save only the display target. Initialization never replaces a saved target,
    /// including when two phones migrate concurrently. Existing body data and zone
    /// remain intact; no analysis is invalidated.
    /// # Errors
    /// Returns a storage error on invalid input or database failure.
    pub async fn save_sleep_goal(
        &self,
        device: &str,
        minutes: i32,
        initialize_only: bool,
        timezone: &str,
    ) -> StorageResult<SleepGoal> {
        let minutes = sqlx::query_scalar(
            "INSERT INTO profiles(device_id,tz,sleep_goal_minutes) VALUES($1,$2,$3)
             ON CONFLICT(device_id) DO UPDATE SET sleep_goal_minutes =
               CASE WHEN $4 THEN COALESCE(profiles.sleep_goal_minutes, EXCLUDED.sleep_goal_minutes)
                    ELSE EXCLUDED.sleep_goal_minutes END
             RETURNING sleep_goal_minutes",
        )
        .bind(device)
        .bind(timezone)
        .bind(minutes)
        .bind(initialize_only)
        .fetch_one(self.pool())
        .await
        .map_err(|e| StorageError::unavailable(StoreOperation::UpsertProfile, e))?;
        Ok(SleepGoal {
            minutes,
            configured: true,
        })
    }
}
