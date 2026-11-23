//! Browser-owned connection management; tokens returned once and never listed.
use crate::{
    auth::browser,
    error::{AgentError, AgentResult},
    permissions::Consent,
    state::AgentState,
};
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
};
use chrono::{Duration, Utc};
use serde_json::{Value, json};
use zoop_auth::{digest, random_token};
use zoop_storage::{AgentCredential, NewAgentConnection};
pub(crate) async fn list(State(s): State<AgentState>, h: HeaderMap) -> AgentResult<Json<Value>> {
    let (a, _) = browser(&s, &h, false).await?;
    Ok(Json(
        json!({"connections":s.store.agent_connections(a.id).await?,"mcp_url":s.resource(),"api_url":format!("{}/v1/agent",s.origin)}),
    ))
}
pub(crate) async fn create(
    State(s): State<AgentState>,
    h: HeaderMap,
    Json(c): Json<Consent>,
) -> AgentResult<Json<Value>> {
    let (a, session) = browser(&s, &h, true).await?;
    c.validate(&s).await?;
    if !s
        .store
        .allow_login(&format!("agent-create:{}", a.id), 20, 3600)
        .await?
    {
        return Err(AgentError::Limited);
    }
    let token = format!(
        "zoop_ak_{}",
        random_token().map_err(|_| AgentError::Unavailable)?
    );
    let expires = Utc::now() + Duration::days(c.expires_in_days);
    let resource = s.resource();
    let n = NewAgentConnection {
        account_id: a.id,
        device: &c.device_id,
        name: c.name.trim(),
        scopes: &c.scopes,
        history_days: c.history_days,
        timezone: &c.timezone,
        client_id: None,
        resource: &resource,
        expires_at: expires,
    };
    let hash = digest(&token);
    let cred = AgentCredential {
        digest: &hash,
        kind: "key",
        expires_at: expires,
        redirect_uri: None,
        challenge: None,
    };
    let row = s
        .store
        .create_agent_connection(&n, &session, &cred)
        .await?
        .ok_or(AgentError::Forbidden)?;
    Ok(Json(json!({"connection":row,"key":token})))
}
pub(crate) async fn revoke(
    State(s): State<AgentState>,
    h: HeaderMap,
    Path(id): Path<i64>,
) -> AgentResult<StatusCode> {
    let (a, _) = browser(&s, &h, true).await?;
    if !s.store.revoke_agent_connection(a.id, id).await? {
        return Err(AgentError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}
