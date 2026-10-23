//! snoop HTTP API.

mod auth;
mod devices;
mod error;
mod ingest;
mod state;

pub use state::AppState;

use axum::{
    Router, middleware,
    routing::{get, post},
};
use tower_http::trace::TraceLayer;

use crate::{
    auth::require_bearer,
    devices::{day, latest},
    ingest::ingest,
};

pub fn build_router(state: AppState) -> Router {
    let protected = Router::new()
        .route("/v1/ingest", post(ingest))
        .route("/v1/devices/{deviceId}/latest", get(latest))
        .route("/v1/devices/{deviceId}/days/{date}", get(day))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_bearer,
        ));

    Router::new()
        .route("/health", get(|| async { "ok" }))
        .merge(protected)
        .with_state(state)
        .layer(TraceLayer::new_for_http())
}
