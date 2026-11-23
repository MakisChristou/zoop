//! Browser consent and agent authorization are separate trust boundaries.
use crate::{
    error::{AgentError, AgentResult},
    state::AgentState,
};
use axum::{
    extract::{Request, State},
    http::{HeaderMap, header},
    middleware::Next,
    response::{IntoResponse, Response},
};
use zoop_auth::digest;
use zoop_storage::{Account, AgentConnection};

pub(crate) async fn browser(
    s: &AgentState,
    h: &HeaderMap,
    write: bool,
) -> AgentResult<(Account, String)> {
    if h.contains_key(header::AUTHORIZATION)
        || (write && h.get(header::ORIGIN).and_then(|v| v.to_str().ok()) != Some(s.origin.as_str()))
    {
        return Err(AgentError::Forbidden);
    }
    let cookie = h
        .get(header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| {
            v.split(';')
                .map(str::trim)
                .find_map(|v| v.strip_prefix("zoop_session="))
        })
        .filter(|v| v.len() == 64 && v.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or(AgentError::Unauthorized)?;
    let hash = digest(cookie);
    let a = s
        .store
        .session_account(&hash)
        .await?
        .ok_or(AgentError::Unauthorized)?;
    Ok((a, hash))
}
pub(crate) async fn agent(s: &AgentState, h: &HeaderMap) -> AgentResult<AgentConnection> {
    // Origin protects browser/DNS-rebinding access; scripts normally omit it.
    if h.contains_key(header::COOKIE)
        || h.get(header::ORIGIN)
            .is_some_and(|v| v.to_str().ok() != Some(s.origin.as_str()))
    {
        return Err(AgentError::Forbidden);
    }
    let token = h
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .filter(|v| v.len() == 72 && (v.starts_with("zoop_ak_") || v.starts_with("zoop_at_")))
        .ok_or(AgentError::Unauthorized)?;
    s.store
        .authenticate_agent(&digest(token), &s.resource())
        .await?
        .ok_or(AgentError::Unauthorized)
}
pub(crate) async fn guard(State(s): State<AgentState>, mut r: Request, next: Next) -> Response {
    let grant = match agent(&s, r.headers()).await {
        Ok(v) => v,
        Err(e) => {
            let mut response = e.into_response();
            if response.status() == 401
                && let Ok(v) = format!(
                    "Bearer resource_metadata=\"{}/.well-known/oauth-protected-resource/mcp\", scope=\"{}\"",
                    s.origin, crate::permissions::SCOPES.join(" ")
                )
                .parse()
            {
                response.headers_mut().insert(header::WWW_AUTHENTICATE, v);
            }
            return response;
        }
    };
    let permit = match s.slots.clone().try_acquire_owned() {
        Ok(p) => p,
        Err(_) => return AgentError::Limited.into_response(),
    };
    match s
        .store
        .allow_login(&format!("agent-read:{}", grant.id), 60, 60)
        .await
    {
        Ok(true) => {}
        Ok(false) => return AgentError::Limited.into_response(),
        Err(_) => return AgentError::Unavailable.into_response(),
    }
    r.extensions_mut().insert(grant);
    let result = tokio::time::timeout(std::time::Duration::from_secs(20), next.run(r)).await;
    drop(permit);
    result.unwrap_or_else(|_| AgentError::Unavailable.into_response())
}
