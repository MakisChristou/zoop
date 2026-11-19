//! Bounded, authenticated-by-caller profile photos stored directly in Postgres.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

impl PostgresStore {
    /// Read the normalized JPEG, or no photo. No public object URLs are created.
    /// # Errors
    /// Database failure.
    pub async fn profile_photo(&self, device: &str) -> StorageResult<Option<Vec<u8>>> {
        sqlx::query_scalar("SELECT jpeg FROM profile_photos WHERE device_id=$1")
            .bind(device)
            .fetch_optional(self.pool())
            .await
            .map_err(|e| StorageError::unavailable(StoreOperation::ProfilePhoto, e))
    }
    /// Replace a photo atomically. Returns false if the device does not exist.
    /// # Errors
    /// Database failure or an oversized image violating the storage constraint.
    pub async fn save_profile_photo(&self, device: &str, jpeg: &[u8]) -> StorageResult<bool> {
        let result = sqlx::query("INSERT INTO profile_photos(device_id,jpeg) SELECT id,$2 FROM devices WHERE id=$1 ON CONFLICT(device_id) DO UPDATE SET jpeg=EXCLUDED.jpeg,updated_at=now()")
            .bind(device).bind(jpeg).execute(self.pool()).await
            .map_err(|e| StorageError::unavailable(StoreOperation::ProfilePhoto,e))?;
        Ok(result.rows_affected() == 1)
    }
    /// Remove only this device's photo. Repeating the operation is harmless.
    /// # Errors
    /// Database failure.
    pub async fn remove_profile_photo(&self, device: &str) -> StorageResult<()> {
        sqlx::query("DELETE FROM profile_photos WHERE device_id=$1")
            .bind(device)
            .execute(self.pool())
            .await
            .map_err(|e| StorageError::unavailable(StoreOperation::ProfilePhoto, e))?;
        Ok(())
    }
}
