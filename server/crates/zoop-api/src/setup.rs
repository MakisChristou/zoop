//! Operator-code-protected first-run setup. There is no public registration.
use crate::{AppState, auth::constant_time_eq, error::ApiError, web::check_origin};
use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode},
};
use secrecy::ExposeSecret;
use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
pub(crate) struct Setup {
    code: String,
    email: String,
    password: String,
    device: Option<String>,
}

pub(crate) async fn status(State(s): State<AppState>) -> Result<Json<Value>, ApiError> {
    let available = s.web.is_some() && s.setup_token.is_some() && s.store.setup_available().await?;
    Ok(Json(json!({"available":available})))
}

pub(crate) async fn complete(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<Setup>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    check_origin(&s, &headers)?;
    let expected = s.setup_token.as_ref().ok_or(ApiError::NotFound)?;
    if !s.store.setup_available().await? {
        return Err(ApiError::NotFound);
    }
    if !s.store.allow_login("first-run-setup", 10, 900).await? {
        return Err(ApiError::RateLimited);
    }
    if input.code.len() > 256
        || !constant_time_eq(
            &zoop_auth::digest(&input.code),
            &zoop_auth::digest(expected.expose_secret()),
        )
    {
        return Err(ApiError::Unauthorized);
    }
    if input.email.len() > 254 || !(12..=256).contains(&input.password.len()) {
        return Err(ApiError::BadRequest(
            "Use an email and a password of 12–256 bytes.".into(),
        ));
    }
    let permit = s
        .password_slots
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::RateLimited)?;
    let hash = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        zoop_auth::hash_password(&input.password)
    })
    .await
    .map_err(|_| ApiError::AuthUnavailable)?
    .map_err(|_| ApiError::AuthUnavailable)?;
    let device = input
        .device
        .as_deref()
        .map(str::trim)
        .filter(|d| !d.is_empty());
    match s.store.complete_setup(&input.email, &hash, device).await? {
        Some(_) => Ok((StatusCode::CREATED, Json(json!({"created": true})))),
        None => Err(ApiError::Conflict(
            "Setup is already complete. Sign in instead.".into(),
        )),
    }
}
