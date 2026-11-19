//! User corrections of a session's kind. Unversioned: a label is matched to whatever
//! session overlaps it, so a recompute at a new algorithm version keeps it.

use chrono::{DateTime, Utc};

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

impl PostgresStore {
    /// Records that the session spanning `[start_ts, end_ts)` is of `kind`.
    pub async fn upsert_label(
        &self,
        device_id: &str,
        start_ts: DateTime<Utc>,
        end_ts: DateTime<Utc>,
        kind: &str,
    ) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO workout_labels (device_id, start_ts, end_ts, kind, updated_at)
             VALUES ($1, $2, $3, $4, now())
             ON CONFLICT (device_id, start_ts) DO UPDATE SET
               end_ts = EXCLUDED.end_ts, kind = EXCLUDED.kind, updated_at = now()",
        )
        .bind(device_id)
        .bind(start_ts)
        .bind(end_ts)
        .bind(kind)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertLabel, source))?;
        Ok(())
    }

    /// Removes labels starting in `[from, to)`. Only tests need this; users never
    /// lose a correction.
    pub async fn delete_labels(
        &self,
        device_id: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<()> {
        sqlx::query(
            "DELETE FROM workout_labels WHERE device_id = $1 AND start_ts >= $2 AND start_ts < $3",
        )
        .bind(device_id)
        .bind(from)
        .bind(to)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertLabel, source))?;
        Ok(())
    }
}
