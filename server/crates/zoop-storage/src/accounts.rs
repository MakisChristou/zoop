//! Account ownership is checked before any device-scoped HTTP handler runs.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use serde::Serialize;
use serde_json::Value;
use sqlx::FromRow;
/// Public identity. Admin privileges never bypass health-data ownership.
#[derive(Debug, Clone, Serialize, FromRow)]
pub struct Account {
    pub id: i64,
    pub email: String,
    pub is_admin: bool,
}
/// Login-only credential row; deliberately redacted in Debug output.
#[derive(FromRow)]
pub struct LoginAccount {
    pub id: i64,
    pub email: String,
    pub is_admin: bool,
    pub password_hash: String,
}
impl std::fmt::Debug for LoginAccount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LoginAccount")
            .field("id", &self.id)
            .finish_non_exhaustive()
    }
}
/// Aggregate pipeline facts, with no device identifiers or health payloads.
#[derive(Debug, Serialize)]
pub struct AdminSnapshot {
    pub database: &'static str,
    pub accounts: i64,
    pub frames_24h: i64,
    pub pending_decode: i64,
    pub failed_decode: i64,
    pub pending_analysis: i64,
    pub failed_analysis: i64,
    pub workers: Value,
    pub ingestion: Value,
    pub recent_jobs: Value,
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Accounts, e)
}
impl PostgresStore {
    /// Refuse opt-in private mode until an admin and ownership mappings exist.
    /// # Errors
    /// Database failure.
    pub async fn private_accounts_ready(&self) -> StorageResult<bool> {
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM accounts WHERE enabled AND is_admin) AND NOT EXISTS(SELECT 1 FROM devices d LEFT JOIN device_owners o ON o.device_id=d.id WHERE o.device_id IS NULL)")
            .fetch_one(self.pool()).await.map_err(fail)
    }

    /// Create a provisioned account; there is no open registration endpoint.
    /// # Errors
    /// Invalid identity, duplicate email or database failure.
    pub async fn create_account(
        &self,
        email: &str,
        hash: &str,
        admin: bool,
    ) -> StorageResult<Account> {
        let email = email.trim().to_lowercase();
        if email.len() > 254 || !email.contains('@') || email.chars().any(char::is_whitespace) {
            return Err(StorageError::InvalidQuery("invalid email".into()));
        }
        sqlx::query_as("INSERT INTO accounts(email,password_hash,is_admin) VALUES($1,$2,$3) RETURNING id,email,is_admin")
            .bind(email).bind(hash).bind(admin).fetch_one(self.pool()).await.map_err(fail)
    }
    /// Look up an enabled account for password verification.
    /// # Errors
    /// Database failure.
    pub async fn login_account(&self, email: &str) -> StorageResult<Option<LoginAccount>> {
        sqlx::query_as(
            "SELECT id,email,is_admin,password_hash FROM accounts WHERE email=$1 AND enabled",
        )
        .bind(email.trim().to_lowercase())
        .fetch_optional(self.pool())
        .await
        .map_err(fail)
    }
    /// Bind a serial explicitly. Existing ownership cannot be overwritten.
    /// # Errors
    /// Unknown account, conflicting ownership or database failure.
    pub async fn bind_account_device(&self, email: &str, device: &str) -> StorageResult<()> {
        if device.is_empty() || device.len() > 128 || device.contains('/') {
            return Err(StorageError::InvalidQuery("invalid device serial".into()));
        }
        sqlx::query("INSERT INTO device_owners(device_id,account_id) VALUES($1,(SELECT id FROM accounts WHERE email=$2 AND enabled))")
            .bind(device).bind(email.trim().to_lowercase()).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Check a device reservation, including before its first ingest.
    /// # Errors
    /// Database failure.
    pub async fn owns_device(&self, id: i64, device: &str) -> StorageResult<bool> {
        sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$2)",
        )
        .bind(id)
        .bind(device)
        .fetch_one(self.pool())
        .await
        .map_err(fail)
    }
    /// List only this account's serials; no global device enumeration is exposed.
    /// # Errors
    /// Database failure.
    pub async fn account_devices(&self, id: i64) -> StorageResult<Vec<String>> {
        sqlx::query_scalar(
            "SELECT device_id FROM device_owners WHERE account_id=$1 ORDER BY device_id",
        )
        .bind(id)
        .fetch_all(self.pool())
        .await
        .map_err(fail)
    }
    /// List owned reservations that have not received a device upload yet.
    /// # Errors
    /// Database failure.
    pub async fn pending_account_devices(&self, id: i64) -> StorageResult<Vec<String>> {
        sqlx::query_scalar("SELECT o.device_id FROM device_owners o LEFT JOIN devices d ON d.id=o.device_id WHERE o.account_id=$1 AND d.id IS NULL ORDER BY o.device_id")
            .bind(id).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Persist a hashed iPhone credential, including an explicitly imported legacy token.
    /// # Errors
    /// Unknown account, duplicate token or database failure.
    pub async fn add_account_token(&self, email: &str, digest: &str) -> StorageResult<()> {
        sqlx::query("INSERT INTO account_tokens(digest,account_id) VALUES($1,(SELECT id FROM accounts WHERE email=$2 AND enabled))")
            .bind(digest).bind(email.trim().to_lowercase()).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Issue a phone credential only if the verified password is still current.
    /// # Errors
    /// Database failure.
    pub async fn create_native_token(
        &self,
        id: i64,
        digest: &str,
        expected_hash: &str,
    ) -> StorageResult<bool> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let account: Option<i64> = sqlx::query_scalar(
            "SELECT id FROM accounts WHERE id=$1 AND enabled AND password_hash=$2 FOR SHARE",
        )
        .bind(id)
        .bind(expected_hash)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        if account.is_none() {
            return Ok(false);
        }
        sqlx::query("INSERT INTO account_tokens(digest,account_id) VALUES($1,$2)")
            .bind(digest)
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(true)
    }
    /// Revoke only the phone credential presented at logout.
    /// # Errors
    /// Database failure.
    pub async fn revoke_account_token(&self, digest: &str) -> StorageResult<()> {
        sqlx::query("DELETE FROM account_tokens WHERE digest=$1")
            .bind(digest)
            .execute(self.pool())
            .await
            .map_err(fail)?;
        Ok(())
    }
    /// Authenticate a hashed bearer credential against a currently enabled account.
    /// # Errors
    /// Database failure.
    pub async fn token_account(&self, digest: &str) -> StorageResult<Option<Account>> {
        sqlx::query_as("SELECT a.id,a.email,a.is_admin FROM account_tokens t JOIN accounts a ON a.id=t.account_id WHERE t.digest=$1 AND a.enabled")
            .bind(digest).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Persist a session with a fixed expiry; expired sessions are pruned opportunistically.
    /// # Errors
    /// Database failure.
    pub async fn create_web_session(
        &self,
        id: i64,
        digest: &str,
        expected_hash: &str,
    ) -> StorageResult<bool> {
        sqlx::query("DELETE FROM web_sessions WHERE expires_at<=now()")
            .execute(self.pool())
            .await
            .map_err(fail)?;
        let mut tx = self.pool().begin().await.map_err(fail)?;
        // Serialize issuance with password reset/disable, including the session insert.
        let account: Option<i64> = sqlx::query_scalar(
            "SELECT id FROM accounts WHERE id=$1 AND enabled AND password_hash=$2 FOR SHARE",
        )
        .bind(id)
        .bind(expected_hash)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        if account.is_none() {
            return Ok(false);
        }
        sqlx::query("INSERT INTO web_sessions(digest,account_id,expires_at) VALUES($1,$2,now()+interval '12 hours')")
            .bind(digest).bind(id).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(true)
    }
    /// Resolve a non-expired session, checking current account state and role.
    /// # Errors
    /// Database failure.
    pub async fn session_account(&self, digest: &str) -> StorageResult<Option<Account>> {
        sqlx::query_as("SELECT a.id,a.email,a.is_admin FROM web_sessions s JOIN accounts a ON a.id=s.account_id WHERE s.digest=$1 AND s.expires_at>now() AND a.enabled")
            .bind(digest).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Revoke one session on logout.
    /// # Errors
    /// Database failure.
    pub async fn revoke_session(&self, digest: &str) -> StorageResult<()> {
        sqlx::query("DELETE FROM web_sessions WHERE digest=$1")
            .bind(digest)
            .execute(self.pool())
            .await
            .map_err(fail)?;
        Ok(())
    }
    /// Fixed-window atomic rate limiting, shared across service instances. Keys are digests.
    /// # Errors
    /// Database failure (login fails closed).
    pub async fn allow_login(&self, key: &str, limit: i32, seconds: i32) -> StorageResult<bool> {
        sqlx::query("DELETE FROM login_limits WHERE window_start<now()-interval '1 day'")
            .execute(self.pool())
            .await
            .map_err(fail)?;
        let attempts:i32=sqlx::query_scalar("INSERT INTO login_limits(bucket,attempts) VALUES($1,1) ON CONFLICT(bucket) DO UPDATE SET attempts=CASE WHEN login_limits.window_start<now()-make_interval(secs=>$2::double precision) THEN 1 ELSE least(login_limits.attempts+1,1000000) END, window_start=CASE WHEN login_limits.window_start<now()-make_interval(secs=>$2::double precision) THEN now() ELSE login_limits.window_start END RETURNING attempts")
            .bind(key).bind(seconds).fetch_one(self.pool()).await.map_err(fail)?;
        Ok(attempts <= limit)
    }
    /// Operator recovery rotates a password and revokes every session and phone token atomically.
    /// # Errors
    /// Unknown account or database failure.
    pub async fn reset_account_password(&self, email: &str, hash: &str) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let id: i64 =
            sqlx::query_scalar("UPDATE accounts SET password_hash=$2 WHERE email=$1 RETURNING id")
                .bind(email.trim().to_lowercase())
                .bind(hash)
                .fetch_one(&mut *tx)
                .await
                .map_err(fail)?;
        sqlx::query("DELETE FROM web_sessions WHERE account_id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        sqlx::query("DELETE FROM account_tokens WHERE account_id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        tx.commit().await.map_err(fail)
    }
    /// Disable an account and revoke all tokens and sessions.
    /// # Errors
    /// Unknown account or database failure.
    pub async fn disable_account(&self, email: &str) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let id: i64 =
            sqlx::query_scalar("UPDATE accounts SET enabled=false WHERE email=$1 RETURNING id")
                .bind(email.trim().to_lowercase())
                .fetch_one(&mut *tx)
                .await
                .map_err(fail)?;
        sqlx::query("DELETE FROM web_sessions WHERE account_id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        sqlx::query("DELETE FROM account_tokens WHERE account_id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        tx.commit().await.map_err(fail)
    }
    /// Aggregate operational statistics. Errors are counted, never returned verbatim.
    /// # Errors
    /// Database failure.
    pub async fn admin_snapshot(&self) -> StorageResult<AdminSnapshot> {
        let (accounts,frames,pending,failed):(i64,i64,i64,i64)=sqlx::query_as("SELECT (SELECT count(*) FROM accounts WHERE enabled),(SELECT count(*) FROM raw_frames WHERE uploaded_at>now()-interval '24 hours'),(SELECT count(*) FROM raw_frames WHERE decoded_proto IS NULL),(SELECT count(*) FROM raw_frames WHERE decode_error IS NOT NULL)")
            .fetch_one(self.pool()).await.map_err(fail)?;
        let (pending_analysis,failed_analysis):(i64,i64)=sqlx::query_as("SELECT count(*) FILTER(WHERE generation>completed_generation),count(*) FILTER(WHERE generation>completed_generation AND last_error IS NOT NULL) FROM analysis_jobs").fetch_one(self.pool()).await.map_err(fail)?;
        let workers:Value=sqlx::query_scalar("SELECT coalesce(jsonb_agg(jsonb_build_object('name',name,'heartbeat_at',heartbeat_at,'last_success',last_success,'paused',paused,'has_error',last_error IS NOT NULL,'healthy',heartbeat_at>now()-interval '2 minutes' AND last_error IS NULL AND NOT paused)),'[]') FROM worker_status").fetch_one(self.pool()).await.map_err(fail)?;
        let ingestion:Value=sqlx::query_scalar("SELECT coalesce(jsonb_agg(jsonb_build_object('hour',x.bucket,'frames',x.frames) ORDER BY x.bucket),'[]') FROM (SELECT date_trunc('hour',uploaded_at) AS bucket,count(*) frames FROM raw_frames WHERE uploaded_at>now()-interval '24 hours' GROUP BY 1) x").fetch_one(self.pool()).await.map_err(fail)?;
        let recent_jobs:Value=sqlx::query_scalar("SELECT coalesce(jsonb_agg(x ORDER BY x.completed_at DESC),'[]') FROM (SELECT kind,completed_at FROM analysis_jobs WHERE completed_at IS NOT NULL ORDER BY completed_at DESC LIMIT 10) x").fetch_one(self.pool()).await.map_err(fail)?;
        Ok(AdminSnapshot {
            database: "reachable",
            accounts,
            frames_24h: frames,
            pending_decode: pending,
            failed_decode: failed,
            pending_analysis,
            failed_analysis,
            workers,
            ingestion,
            recent_jobs,
        })
    }
}
