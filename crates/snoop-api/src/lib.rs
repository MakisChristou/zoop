//! snoop HTTP API.

mod auth;
mod days;
mod devices;
mod epochs;
mod error;
mod health;
mod ingest;
mod insights;
mod processing;
mod profile;
mod profile_photo;
mod progress;
mod query;
mod sleep_sessions;
mod sleeps;
mod state;
mod steps;
mod weight_goal;
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
            "/v1/devices/{deviceId}/weight-goal",
            get(weight_goal::get).put(weight_goal::put),
        )
        .route("/v1/devices/{deviceId}/progress", get(progress::progress))
        .route("/v1/devices/{deviceId}/health", get(health::info))
        .route(
            "/v1/devices/{deviceId}/health/exports",
            get(health::exports),
        )
        .route(
            "/v1/devices/{deviceId}/health/prepare",
            post(health::prepare),
        )
        .route(
            "/v1/devices/{deviceId}/weight-changes",
            get(health::weight_changes),
        )
        .route(
            "/v1/devices/{deviceId}/weights",
            get(health::weights).put(health::save_weight),
        )
        .route(
            "/v1/devices/{deviceId}/weights/remove-imports",
            post(health::remove_imports),
        )
        .route(
            "/v1/devices/{deviceId}/processing",
            get(processing::processing),
        )
        .route(
            "/v1/devices/{deviceId}/days/{date}/insights",
            get(insights::insights),
        )
        .route("/v1/ingest", post(ingest))
        .route("/v2/ingest", post(ingest_v2))
        .route("/v1/devices/{deviceId}/latest", get(latest))
        .route("/v1/devices/{deviceId}/days/{date}", get(day))
        .route("/v1/devices/{deviceId}/days/{date}/steps", get(steps))
        .route("/v1/devices/{deviceId}/sleeps", get(sleeps))
        .route(
            "/v1/devices/{deviceId}/sleep-sessions",
            get(sleep_sessions::list),
        )
        .route(
            "/v1/devices/{deviceId}/sleep-sessions/{id}",
            get(sleep_sessions::get),
        )
        .route(
            "/v1/devices/{deviceId}/sleep-sessions/{id}/epochs",
            get(sleep_sessions::epochs),
        )
        .route(
            "/v1/devices/{deviceId}/sleep-sessions/corrections",
            post(sleep_sessions::correct),
        )
        .route(
            "/v1/devices/{deviceId}/analysis/reset-preview",
            post(sleep_sessions::preview_reset),
        )
        .route(
            "/v1/devices/{deviceId}/analysis/reset",
            post(sleep_sessions::reset),
        )
        .route(
            "/v1/devices/{deviceId}/analysis/reset-undo",
            post(sleep_sessions::undo_reset),
        )
        .route(
            "/v1/devices/{deviceId}/analysis/resets",
            get(sleep_sessions::resets),
        )
        .route("/v1/devices/{deviceId}/days", get(days))
        .route(
            "/v1/devices/{deviceId}/sleeps/{nightOf}/epochs",
            get(epochs),
        )
        .route("/v1/devices/{deviceId}/workouts", get(workouts))
        .route(
            "/v1/devices/{deviceId}/workouts/corrections",
            post(workouts::correct),
        )
        .route(
            "/v1/devices/{deviceId}/workouts/{id}",
            get(workouts::workout),
        )
        .route("/v1/devices/{deviceId}/workouts/{id}/kind", put(set_kind))
        .route(
            "/v1/devices/{deviceId}/profile",
            get(get_profile).put(put_profile),
        )
        .route(
            "/v1/devices/{deviceId}/profile/photo",
            get(profile_photo::get)
                .put(profile_photo::put)
                .delete(profile_photo::delete)
                .layer(axum::extract::DefaultBodyLimit::max(
                    profile_photo::MAX_BYTES,
                )),
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
