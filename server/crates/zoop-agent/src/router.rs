//! Mounted only when private accounts are enabled.
use crate::{auth, connections, data, mcp::AgentMcp, oauth, state::AgentState};
use axum::{
    Router,
    extract::DefaultBodyLimit,
    middleware,
    routing::{get, post},
};
use rmcp::transport::streamable_http_server::{
    StreamableHttpServerConfig, StreamableHttpService, session::local::LocalSessionManager,
};
use std::sync::Arc;
/// Build the agent and OAuth boundary. Never mounts phone or administrator tools.
pub fn router(s: AgentState) -> Router {
    let mcp_state = s.clone();
    let authority = url::Url::parse(&s.origin)
        .ok()
        .map(|u| u[url::Position::BeforeHost..url::Position::AfterPort].to_owned())
        .unwrap_or_else(|| "invalid.invalid".into());
    let mut config = StreamableHttpServerConfig::default().with_allowed_hosts([authority]);
    config.legacy_session_mode = false;
    config.json_response = true;
    config.max_request_body_bytes = 16 * 1024;
    let mcp = StreamableHttpService::new(
        move || Ok(AgentMcp(mcp_state.clone())),
        Arc::new(LocalSessionManager::default()),
        config,
    );
    let reads = Router::new()
        .route("/v1/agent/{tool}", get(data::http))
        .route_service("/mcp", mcp)
        .layer(middleware::from_fn_with_state(s.clone(), auth::guard));
    Router::new()
        .route("/v1/agent-openapi.json", get(crate::openapi::schema))
        .route(
            "/v1/agent-connections",
            get(connections::list).post(connections::create),
        )
        .route(
            "/v1/agent-connections/{id}",
            axum::routing::delete(connections::revoke),
        )
        .route(
            "/.well-known/oauth-authorization-server",
            get(oauth::metadata),
        )
        .route(
            "/.well-known/oauth-protected-resource/mcp",
            get(oauth::resource_metadata),
        )
        .route("/oauth/register", post(oauth::register))
        .route("/oauth/authorize", get(oauth::authorize))
        .route("/oauth/token", post(oauth::token))
        .route(
            "/v1/agent-authorization",
            get(oauth::details).post(oauth::approve),
        )
        .merge(reads)
        .layer(DefaultBodyLimit::max(16 * 1024))
        .with_state(s)
}
