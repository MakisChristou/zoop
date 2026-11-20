//! First-admin setup is possible only on an empty installation.
use crate::{Account, PostgresStore, StorageError, StorageResult, StoreOperation};

fn fail(error: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Accounts, error)
}

impl PostgresStore {
    /// Whether browser setup may initialize this installation.
    /// # Errors
    /// Database failure. Existing accounts or device data always disable setup.
    pub async fn setup_available(&self) -> StorageResult<bool> {
        sqlx::query_scalar("SELECT NOT EXISTS(SELECT 1 FROM accounts) AND NOT EXISTS(SELECT 1 FROM devices) AND NOT EXISTS(SELECT 1 FROM device_owners)")
            .fetch_one(self.pool()).await.map_err(fail)
    }

    /// Atomically create the first administrator and an optional device reservation.
    /// # Errors
    /// Invalid input or database failure. Returns `None` if setup was already used.
    pub async fn complete_setup(
        &self,
        email: &str,
        password_hash: &str,
        device: Option<&str>,
    ) -> StorageResult<Option<Account>> {
        let email = email.trim().to_lowercase();
        if email.len() > 254 || !email.contains('@') || email.chars().any(char::is_whitespace) {
            return Err(StorageError::InvalidQuery("invalid email".into()));
        }
        if device.is_some_and(|d| {
            d.is_empty() || d.len() > 128 || d.contains('/') || d.chars().any(char::is_whitespace)
        }) {
            return Err(StorageError::InvalidQuery("invalid device serial".into()));
        }
        let mut tx = self.pool().begin().await.map_err(fail)?;
        // Also serialize with operator CLI account/device creation, not just other
        // HTTP setup requests. Locks and the empty check are in one transaction.
        sqlx::query("LOCK TABLE accounts, devices, device_owners IN SHARE ROW EXCLUSIVE MODE")
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let available: bool = sqlx::query_scalar("SELECT NOT EXISTS(SELECT 1 FROM accounts) AND NOT EXISTS(SELECT 1 FROM devices) AND NOT EXISTS(SELECT 1 FROM device_owners)")
            .fetch_one(&mut *tx).await.map_err(fail)?;
        if !available {
            return Ok(None);
        }
        let account: Account = sqlx::query_as("INSERT INTO accounts(email,password_hash,is_admin) VALUES($1,$2,true) RETURNING id,email,is_admin")
            .bind(email).bind(password_hash).fetch_one(&mut *tx).await.map_err(fail)?;
        if let Some(device) = device {
            sqlx::query("INSERT INTO device_owners(device_id,account_id) VALUES($1,$2)")
                .bind(device)
                .bind(account.id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
        }
        tx.commit().await.map_err(fail)?;
        Ok(Some(account))
    }
}
