//! Per-account grants. Opaque credentials are stored only as digests.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;

/// Consent record, never a bearer credential.
#[derive(Debug, Clone, Serialize, FromRow)]
pub struct AgentConnection {
    /// Stable revocation handle.
    pub id: i64,
    /// Owning account, never supplied by an agent.
    #[serde(skip_serializing)]
    pub account_id: i64,
    /// Fixed owned data source.
    #[serde(skip_serializing)]
    pub device_id: String,
    /// User-facing connection name.
    pub name: String,
    /// Explicit read permissions.
    pub scopes: Vec<String>,
    /// Rolling history allowance; None means all history.
    pub history_days: Option<i32>,
    /// Fixed consent timezone.
    pub timezone: String,
    /// OAuth client, absent for access keys.
    pub client_id: Option<String>,
    /// Intended resource URL.
    pub resource: String,
    /// Absolute grant expiry.
    pub expires_at: DateTime<Utc>,
    /// Revocation timestamp.
    pub revoked_at: Option<DateTime<Utc>>,
    /// Creation timestamp.
    pub created_at: DateTime<Utc>,
    /// Last authenticated access.
    pub last_used_at: Option<DateTime<Utc>>,
}
/// Explicit grant creation, after browser authentication and consent.
#[derive(Debug)]
pub struct NewAgentConnection<'a> {
    /// Account identified from the session.
    pub account_id: i64,
    /// Owned device selected at consent.
    pub device: &'a str,
    /// Display name.
    pub name: &'a str,
    /// Read scopes.
    pub scopes: &'a [String],
    /// Rolling window.
    pub history_days: Option<i32>,
    /// IANA timezone.
    pub timezone: &'a str,
    /// Optional registered client.
    pub client_id: Option<&'a str>,
    /// Resource audience.
    pub resource: &'a str,
    /// Grant expiry.
    pub expires_at: DateTime<Utc>,
}
/// A registered public OAuth client; no fetched metadata or client secrets.
#[derive(Debug, Clone, Serialize, FromRow)]
pub struct AgentClient {
    /// Random client identifier.
    pub id: String,
    /// Untrusted display name.
    pub name: String,
    /// Exact allowed callbacks.
    pub redirect_uris: Vec<String>,
}
/// Hashed issuance parameters, never raw credentials.
#[derive(Debug)]
pub struct AgentCredential<'a> {
    /// SHA256 digest.
    pub digest: &'a str,
    /// key or code.
    pub kind: &'a str,
    /// Initial credential expiry.
    pub expires_at: DateTime<Utc>,
    /// Exact OAuth callback.
    pub redirect_uri: Option<&'a str>,
    /// S256 challenge.
    pub challenge: Option<&'a str>,
}
/// An atomic OAuth exchange; failed bindings do not consume the credential.
#[derive(Debug)]
pub struct AgentExchange<'a> {
    /// Presented code/refresh digest.
    pub digest: &'a str,
    /// code or refresh.
    pub kind: &'a str,
    /// Registered client.
    pub client_id: &'a str,
    /// Resource audience.
    pub resource: &'a str,
    /// Required for a code exchange.
    pub redirect_uri: Option<&'a str>,
    /// Hash of PKCE verifier.
    pub challenge: Option<&'a str>,
    /// New access credential digest.
    pub access: &'a str,
    /// New refresh credential digest.
    pub refresh: &'a str,
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::AgentAccess, e)
}
impl PostgresStore {
    /// Register a public OAuth client. Caller rate-limits registration.
    /// # Errors
    /// Database failure.
    pub async fn register_agent_client(
        &self,
        id: &str,
        name: &str,
        redirects: &[String],
    ) -> StorageResult<()> {
        sqlx::query("INSERT INTO agent_clients(id,name,redirect_uris) VALUES($1,$2,$3)")
            .bind(id)
            .bind(name)
            .bind(redirects)
            .execute(self.pool())
            .await
            .map_err(fail)?;
        Ok(())
    }
    /// Cache validated public client metadata. Never changes existing grants.
    /// # Errors
    /// Database failure.
    pub async fn cache_agent_client(&self, client: &AgentClient) -> StorageResult<()> {
        sqlx::query("INSERT INTO agent_clients(id,name,redirect_uris) VALUES($1,$2,$3) ON CONFLICT(id) DO UPDATE SET name=excluded.name,redirect_uris=excluded.redirect_uris")
            .bind(&client.id).bind(&client.name).bind(&client.redirect_uris)
            .execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Purge abandoned registrations; preserve every client referenced by a grant.
    /// # Errors
    /// Database failure.
    pub async fn purge_unused_agent_clients(&self) -> StorageResult<()> {
        sqlx::query("DELETE FROM agent_clients c WHERE created_at < now()-interval '7 days' AND NOT EXISTS(SELECT 1 FROM agent_connections g WHERE g.client_id=c.id)")
            .execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Resolve only locally registered metadata.
    /// # Errors
    /// Database failure.
    pub async fn agent_client(&self, id: &str) -> StorageResult<Option<AgentClient>> {
        sqlx::query_as("SELECT id,name,redirect_uris FROM agent_clients WHERE id=$1")
            .bind(id)
            .fetch_optional(self.pool())
            .await
            .map_err(fail)
    }
    /// Issue a grant while serializing against session revocation/account deletion.
    /// # Errors
    /// Database failure or expired session/ownership.
    pub async fn create_agent_connection(
        &self,
        n: &NewAgentConnection<'_>,
        session: &str,
        c: &AgentCredential<'_>,
    ) -> StorageResult<Option<AgentConnection>> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let valid:Option<i64>=sqlx::query_scalar("SELECT a.id FROM accounts a JOIN web_sessions s ON s.account_id=a.id JOIN device_owners d ON d.account_id=a.id WHERE a.id=$1 AND a.enabled AND s.digest=$2 AND s.expires_at>now() AND d.device_id=$3 FOR UPDATE OF a FOR SHARE OF s,d")
            .bind(n.account_id).bind(session).bind(n.device).fetch_optional(&mut *tx).await.map_err(fail)?;
        if valid.is_none() {
            return Ok(None);
        }
        let count:i64=sqlx::query_scalar("SELECT count(*) FROM agent_connections WHERE account_id=$1 AND revoked_at IS NULL AND expires_at>now()")
            .bind(n.account_id).fetch_one(&mut *tx).await.map_err(fail)?;
        if count >= 50 {
            return Err(StorageError::InvalidQuery(
                "Revoke an existing connection first.".into(),
            ));
        }
        // Expired access tokens cannot be replayed. Keep consumed refreshes/codes
        // for the live grant's lifetime to detect credential reuse.
        sqlx::query("DELETE FROM agent_credentials WHERE kind='access' AND expires_at<=now()")
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let row:AgentConnection=sqlx::query_as("INSERT INTO agent_connections(account_id,device_id,name,scopes,history_days,timezone,client_id,resource,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *")
            .bind(n.account_id).bind(n.device).bind(n.name).bind(n.scopes).bind(n.history_days).bind(n.timezone).bind(n.client_id).bind(n.resource).bind(n.expires_at).fetch_one(&mut *tx).await.map_err(fail)?;
        sqlx::query("INSERT INTO agent_credentials(digest,connection_id,kind,expires_at,redirect_uri,challenge) VALUES($1,$2,$3,$4,$5,$6)")
            .bind(c.digest).bind(row.id).bind(c.kind).bind(c.expires_at).bind(c.redirect_uri).bind(c.challenge).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(Some(row))
    }
    /// List only the owner's grants; no token material.
    /// # Errors
    /// Database failure.
    pub async fn agent_connections(&self, owner: i64) -> StorageResult<Vec<AgentConnection>> {
        sqlx::query_as("SELECT * FROM agent_connections WHERE account_id=$1 ORDER BY (revoked_at IS NULL AND expires_at>now()) DESC,created_at DESC LIMIT 100").bind(owner).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Revoke only an owned connection, including its outstanding codes and refreshes.
    /// # Errors
    /// Database failure.
    pub async fn revoke_agent_connection(&self, owner: i64, id: i64) -> StorageResult<bool> {
        Ok(sqlx::query("UPDATE agent_connections SET revoked_at=coalesce(revoked_at,now()) WHERE account_id=$1 AND id=$2").bind(owner).bind(id).execute(self.pool()).await.map_err(fail)?.rows_affected()>0)
    }
    /// Revalidate account, device ownership, grant and credential on every request.
    /// # Errors
    /// Database failure.
    pub async fn authenticate_agent(
        &self,
        digest: &str,
        resource: &str,
    ) -> StorageResult<Option<AgentConnection>> {
        sqlx::query_as("UPDATE agent_connections g SET last_used_at=now() FROM agent_credentials c,accounts a,device_owners d WHERE c.digest=$1 AND c.connection_id=g.id AND c.kind IN ('key','access') AND NOT c.consumed AND c.expires_at>now() AND g.expires_at>now() AND g.revoked_at IS NULL AND g.resource=$2 AND a.id=g.account_id AND a.enabled AND d.account_id=g.account_id AND d.device_id=g.device_id RETURNING g.*")
            .bind(digest).bind(resource).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Rotate refreshes, enforce PKCE and revoke the family on replay.
    /// # Errors
    /// Database failure.
    pub async fn exchange_agent_credential(
        &self,
        x: &AgentExchange<'_>,
    ) -> StorageResult<Option<AgentConnection>> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let grant:Option<AgentConnection>=sqlx::query_as("SELECT g.* FROM agent_connections g JOIN agent_credentials c ON c.connection_id=g.id JOIN accounts a ON a.id=g.account_id JOIN device_owners d ON d.account_id=a.id AND d.device_id=g.device_id WHERE c.digest=$1 AND c.kind=$2 AND g.client_id=$3 AND g.resource=$4 AND g.revoked_at IS NULL AND g.expires_at>now() AND a.enabled FOR UPDATE OF g,c")
            .bind(x.digest).bind(x.kind).bind(x.client_id).bind(x.resource).fetch_optional(&mut *tx).await.map_err(fail)?;
        let Some(g) = grant else { return Ok(None) };
        let (consumed,expires,redirect,challenge):(bool,DateTime<Utc>,Option<String>,Option<String>)=sqlx::query_as("SELECT consumed,expires_at,redirect_uri,challenge FROM agent_credentials WHERE digest=$1")
            .bind(x.digest).fetch_one(&mut *tx).await.map_err(fail)?;
        if x.kind == "code"
            && (redirect.as_deref() != x.redirect_uri || challenge.as_deref() != x.challenge)
        {
            return Ok(None);
        }
        if consumed {
            sqlx::query("UPDATE agent_connections SET revoked_at=now() WHERE id=$1")
                .bind(g.id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
            tx.commit().await.map_err(fail)?;
            return Ok(None);
        }
        if expires <= Utc::now() {
            return Ok(None);
        }
        sqlx::query("UPDATE agent_credentials SET consumed=true WHERE digest=$1")
            .bind(x.digest)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        sqlx::query("INSERT INTO agent_credentials(digest,connection_id,kind,expires_at) VALUES($1,$3,'access',least($4,now()+interval '1 hour')),($2,$3,'refresh',least($4,now()+interval '30 days'))")
            .bind(x.access).bind(x.refresh).bind(g.id).bind(g.expires_at).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(Some(g))
    }
    /// Validate the zone with Postgres, the existing calendar authority.
    /// # Errors
    /// Database failure.
    pub async fn agent_timezone_valid(&self, tz: &str) -> StorageResult<bool> {
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)")
            .bind(tz)
            .fetch_one(self.pool())
            .await
            .map_err(fail)
    }
}
