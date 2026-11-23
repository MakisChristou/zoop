//! zoop HTTP API.

mod auth;
mod telemetry;
mod web;
pub use web::WebOptions;
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
mod setup;
mod sharing;
mod sleep_goal;
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
    let agents = state
        .web
        .as_ref()
        .map(|web| {
            zoop_agent::router(zoop_agent::AgentState::new(
                state.store.clone(),
                web.origin.clone(),
            ))
        })
        .unwrap_or_default();
    let protected = Router::new()
        .route(
            "/v1/devices/{deviceId}/weight-goal",
            get(weight_goal::get).put(weight_goal::put),
        )
        .route(
            "/v1/devices/{deviceId}/weight-goals",
            get(weight_goal::history),
        )
        .route(
            "/v1/devices/{deviceId}/weight-goals/{id}",
            get(weight_goal::detail),
        )
        .route("/v1/devices/{deviceId}/progress", get(progress::progress))
        .route(
            "/v1/devices/{deviceId}/recovery",
            get(insights::recovery_history),
        )
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
        .route(
            "/v1/devices/{deviceId}/sleep-goal",
            get(sleep_goal::get).put(sleep_goal::put),
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
        .merge(
            Router::new()
                .route(
                    "/v1/dashboard-layouts/{device}",
                    get(sharing::get_layout).put(sharing::save_layout),
                )
                .route("/v1/shares", get(sharing::list).post(sharing::create))
                .route("/v1/shares/preview", post(sharing::preview))
                .route(
                    "/v1/shares/{id}",
                    axum::routing::put(sharing::update).delete(sharing::remove),
                )
                .route("/v1/public/dashboard", post(sharing::visit))
                .layer(axum::extract::DefaultBodyLimit::max(16 * 1024)),
        )
        .merge(
            Router::new()
                .route("/v1/setup", get(setup::status).post(setup::complete))
                .layer(axum::extract::DefaultBodyLimit::max(4096)),
        )
        .merge(
            Router::new()
                .route("/v1/account", axum::routing::delete(web::delete_account))
                .layer(axum::extract::DefaultBodyLimit::max(4096)),
        )
        .route("/v1/auth/login", post(web::login))
        .route("/v1/auth/native/login", post(web::native_login))
        .route("/v1/auth/native/logout", post(web::native_logout))
        .route("/v1/auth/logout", post(web::logout))
        .route("/v1/auth/me", get(web::me))
        .route("/v1/admin/stats", get(web::admin))
        .route("/health", get(|| async { "ok" }))
        .route("/ready", get(processing::ready))
        .merge(protected)
        .layer(middleware::from_fn_with_state(
            state.clone(),
            telemetry::observe,
        ))
        .with_state(state)
        .merge(agents)
        .layer(TraceLayer::new_for_http())
        .layer(middleware::from_fn(auth::agent_boundary))
        .layer(middleware::from_fn(no_store))
}

async fn no_store(
    request: axum::extract::Request,
    next: middleware::Next,
) -> axum::response::Response {
    let mut response = next.run(request).await;
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static("no-store"),
    );
    response
}
