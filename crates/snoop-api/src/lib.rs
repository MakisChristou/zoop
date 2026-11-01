//! snoop HTTP API.

mod auth;
mod days;
mod devices;
mod epochs;
mod error;
mod ingest;
mod processing;
mod profile;
mod query;
mod sleeps;
mod state;
mod steps;
mod workouts;

pub use state::AppState;

use axum::{
    Router, middleware,
    routing::{get, post, put},
};
use tower_http::trace::TraceLayer;

use crate::{
    auth::require_bearer,
    days::days,
    devices::{day, latest},
    epochs::epochs,
    ingest::{ingest, ingest_v2},
    profile::{get_profile, put_profile},
    sleeps::sleeps,
    steps::steps,
    workouts::{set_kind, workouts},
};

pub fn build_router(state: AppState) -> Router {
    let protected = Router::new()
        .route(
            "/v1/devices/{deviceId}/processing",
            get(processing::processing),
        )
        .route("/v1/ingest", post(ingest))
        .route("/v2/ingest", post(ingest_v2))
        .route("/v1/devices/{deviceId}/latest", get(latest))
        .route("/v1/devices/{deviceId}/days/{date}", get(day))
        .route("/v1/devices/{deviceId}/days/{date}/steps", get(steps))
        .route("/v1/devices/{deviceId}/sleeps", get(sleeps))
        .route("/v1/devices/{deviceId}/days", get(days))
        .route(
            "/v1/devices/{deviceId}/sleeps/{nightOf}/epochs",
            get(epochs),
        )
        .route("/v1/devices/{deviceId}/workouts", get(workouts))
        .route("/v1/devices/{deviceId}/workouts/{id}/kind", put(set_kind))
        .route(
            "/v1/devices/{deviceId}/profile",
            get(get_profile).put(put_profile),
        )
        .layer(middleware::from_fn_with_state(
            state.clone(),
            require_bearer,
        ));

    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/ready", get(processing::ready))
        .merge(protected)
        .with_state(state)
        .layer(TraceLayer::new_for_http())
}
