//! Explicit owner-requested erasure is the sole exception to raw-frame retention.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

/// Result of a password-verified account deletion.
#[derive(Debug, PartialEq, Eq)]
pub enum AccountDeletion {
    Deleted,
    CredentialsChanged,
    LastAdministrator,
}

fn fail(error: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Accounts, error)
}

impl PostgresStore {
    /// Erase only this account and its explicitly owned devices, in one transaction.
    /// Password changes invalidate the caller's earlier password verification.
    /// # Errors
    /// Database failure rolls back the complete deletion.
    pub async fn delete_account(
        &self,
        id: i64,
        expected_hash: &str,
    ) -> StorageResult<AccountDeletion> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        // Serialize administrator mutations, including CLI disable/reset and setup.
        sqlx::query("LOCK TABLE accounts IN SHARE ROW EXCLUSIVE MODE")
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let admin: Option<bool> = sqlx::query_scalar(
            "SELECT is_admin FROM accounts WHERE id=$1 AND enabled AND password_hash=$2 FOR UPDATE",
        )
        .bind(id)
        .bind(expected_hash)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        let Some(admin) = admin else {
            return Ok(AccountDeletion::CredentialsChanged);
        };
        if admin {
            let other: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM accounts WHERE id<>$1 AND enabled AND is_admin)",
            )
            .bind(id)
            .fetch_one(&mut *tx)
            .await
            .map_err(fail)?;
            if !other {
                return Ok(AccountDeletion::LastAdministrator);
            }
        }
        let devices: Vec<String> = sqlx::query_scalar(
            "SELECT device_id FROM device_owners WHERE account_id=$1 ORDER BY device_id FOR UPDATE",
        )
        .bind(id)
        .fetch_all(&mut *tx)
        .await
        .map_err(fail)?;
        // Fence worker publications and device-scoped writes before removing children.
        sqlx::query("SELECT id FROM devices WHERE id=ANY($1) ORDER BY id FOR UPDATE")
            .bind(&devices)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        for (aliases, sessions) in [
            ("workout_aliases", "workout_sessions"),
            ("sleep_aliases", "sleep_sessions"),
        ] {
            sqlx::query(&format!("DELETE FROM {aliases} WHERE session_id IN (SELECT id FROM {sessions} WHERE device_id=ANY($1))"))
                .bind(&devices).execute(&mut *tx).await.map_err(fail)?;
        }
        // Static identifiers only. Samples are removed before their invalidation
        // projections; health_changes intentionally has no FK and is explicit here.
        for table in [
            "samples",
            "events",
            "ecg_strips",
            "workout_sessions",
            "sleep_sessions",
            "workout_corrections",
            "sleep_corrections",
            "analysis_resets",
            "workout_labels",
            "workouts",
            "sleeps",
            "recoveries",
            "strains",
            "journal",
            "analysis_jobs",
            "analysis_bootstraps",
            "profile_revisions",
            "profile_photos",
            "dashboard_layouts",
            // Credentials cascade from their connection, including revoked grants.
            "agent_connections",
            "profiles",
            "weight_readings",
            "weight_cursors",
            "weight_goal_history",
            "weight_goal_revisions",
            "weight_goals",
            "health_changes",
            "health_exports",
            "health_step_bootstraps",
            "health_datasets",
            "sample_days",
            "day_summary_cache",
            "recovery_observations",
            "recovery_jobs",
            "raw_frames",
        ] {
            sqlx::query(&format!("DELETE FROM {table} WHERE device_id=ANY($1)"))
                .bind(&devices)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
        }
        sqlx::query("DELETE FROM shared_dashboards WHERE account_id=$1 OR device_id=ANY($2)")
            .bind(id)
            .bind(&devices)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        sqlx::query("DELETE FROM devices WHERE id=ANY($1)")
            .bind(&devices)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        for table in ["device_owners", "account_tokens", "web_sessions"] {
            sqlx::query(&format!("DELETE FROM {table} WHERE account_id=$1"))
                .bind(id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
        }
        sqlx::query("DELETE FROM accounts WHERE id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(AccountDeletion::Deleted)
    }
}

/// Keeps account ownership stable until a device mutation has finished.
/// Dropping this read-only transaction releases its row locks.
#[derive(Debug)]
pub struct AccountWriteLease {
    _transaction: sqlx::Transaction<'static, sqlx::Postgres>,
}
impl PostgresStore {
    /// Fence a device mutation against deletion or reassignment.
    /// # Errors
    /// Returns an error when ownership was revoked or the database is unavailable.
    pub async fn account_write_lease(
        &self,
        account: i64,
        device: &str,
    ) -> StorageResult<AccountWriteLease> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let owner: Option<i64> = sqlx::query_scalar("SELECT a.id FROM accounts a JOIN device_owners o ON o.account_id=a.id WHERE a.id=$1 AND a.enabled AND o.device_id=$2 FOR SHARE OF a,o")
            .bind(account).bind(device).fetch_optional(&mut *tx).await.map_err(fail)?;
        if owner.is_none() {
            return Err(StorageError::InvalidQuery(
                "account no longer owns this device".into(),
            ));
        }
        Ok(AccountWriteLease { _transaction: tx })
    }
}
