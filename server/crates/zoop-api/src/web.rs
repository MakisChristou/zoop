//! Browser sessions are read-only; the operator provisions accounts out of band.
use crate::{
    AppState,
    auth::{Principal, session_token},
    error::ApiError,
};
use axum::{
    Json,
    extract::State,
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::json;
use zoop_auth::{digest, hash_password, random_token, verify_password};
/// Browser access configuration. Constructed only after configuration validation.
#[derive(Debug, Clone)]
pub struct WebOptions {
    pub origin: String,
    pub secure_cookie: bool,
}
#[derive(Deserialize)]
pub(crate) struct Login {
    email: String,
    password: String,
}
pub(crate) fn check_origin(s: &AppState, h: &HeaderMap) -> Result<(), ApiError> {
    let config = s.web.as_ref().ok_or(ApiError::NotFound)?;
    if h.get(header::ORIGIN).and_then(|v| v.to_str().ok()) != Some(config.origin.as_str()) {
        return Err(ApiError::Forbidden);
    }
    Ok(())
}
fn cookie(s: &AppState, token: &str, age: i32) -> Result<HeaderValue, ApiError> {
    let config = s.web.as_ref().ok_or(ApiError::NotFound)?;
    HeaderValue::from_str(&format!(
        "zoop_session={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age={age}{}",
        if config.secure_cookie { "; Secure" } else { "" }
    ))
    .map_err(|_| ApiError::AuthUnavailable)
}
pub(crate) async fn login(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<Login>,
) -> Result<Response, ApiError> {
    check_origin(&s, &headers)?;
    let a = verify_login(&s, input).await?;
    let token = random_token().map_err(|_| ApiError::AuthUnavailable)?;
    if !s
        .store
        .create_web_session(a.id, &digest(&token), &a.password_hash)
        .await?
    {
        return Err(ApiError::Unauthorized);
    }
    Ok((
        [(header::SET_COOKIE, cookie(&s, &token, 43200)?)],
        Json(json!({"id":a.id,"email":a.email,"is_admin":a.is_admin})),
    )
        .into_response())
}
pub(crate) async fn logout(
    State(s): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    check_origin(&s, &headers)?;
    if let Some(token) = session_token(&headers) {
        s.store.revoke_session(&digest(token)).await?;
    }
    Ok((
        StatusCode::NO_CONTENT,
        [(header::SET_COOKIE, cookie(&s, "", 0)?)],
    )
        .into_response())
}
pub(crate) async fn me(
    State(s): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let p = crate::auth::authenticate(&s, &headers).await?;
    let a = match p {
        Principal::Browser(a) | Principal::Device(a) => a,
        _ => return Err(ApiError::Forbidden),
    };
    Ok(Json(
        json!({"account":a,"devices":s.store.account_devices(a.id).await?,"pending_devices":s.store.pending_account_devices(a.id).await?}),
    ))
}
pub(crate) async fn admin(
    State(s): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let p = crate::auth::authenticate(&s, &headers).await?;
    if !matches!(p,Principal::Browser(ref a) if a.is_admin) {
        return Err(ApiError::Forbidden);
    }
    Ok(Json(
        json!({"pipeline":s.store.admin_snapshot(zoop_storage::AnalysisVersions { sleep: zoop_analytics::ALGO_VERSION, workout: zoop_analytics::WORKOUT_ALGO_VERSION }).await?,"http":s.telemetry.snapshot()}),
    ))
}

// Password verification and rate limits are shared by browser and phone login.
async fn verify_login(s: &AppState, input: Login) -> Result<zoop_storage::LoginAccount, ApiError> {
    if s.web.is_none() {
        return Err(ApiError::NotFound);
    }
    if input.email.len() > 254 || input.password.len() > 256 {
        return Err(ApiError::Unauthorized);
    }
    if !s.store.allow_login("global", 60, 60).await?
        || !s
            .store
            .allow_login(&digest(&input.email.trim().to_lowercase()), 10, 900)
            .await?
    {
        return Err(ApiError::RateLimited);
    }
    let permit = s
        .password_slots
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::RateLimited)?;
    let account = s.store.login_account(&input.email).await?;
    // Unknown users perform the same expensive operation to avoid a cheap timing oracle.
    let hash = account.as_ref().map(|a| a.password_hash.clone());
    let valid = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        match hash {
            Some(h) => verify_password(&input.password, &h),
            None => {
                let _ = hash_password("unknown account dummy password");
                false
            }
        }
    })
    .await
    .map_err(|_| ApiError::AuthUnavailable)?;
    account.filter(|_| valid).ok_or(ApiError::Unauthorized)
}

/// Native credentials never enter browser cookies or browser-accessible responses.
pub(crate) async fn native_login(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<Login>,
) -> Result<Json<serde_json::Value>, ApiError> {
    if headers.contains_key(header::ORIGIN) || headers.contains_key(header::COOKIE) {
        return Err(ApiError::Forbidden);
    }
    let a = verify_login(&s, input).await?;
    let token = random_token().map_err(|_| ApiError::AuthUnavailable)?;
    if !s
        .store
        .create_native_token(a.id, &digest(&token), &a.password_hash)
        .await?
    {
        return Err(ApiError::Unauthorized);
    }
    Ok(Json(
        json!({"token": token, "account": {"id":a.id,"email":a.email,"is_admin":a.is_admin}, "devices":s.store.account_devices(a.id).await?}),
    ))
}
pub(crate) async fn native_logout(
    State(s): State<AppState>,
    headers: HeaderMap,
) -> Result<StatusCode, ApiError> {
    if !matches!(
        crate::auth::authenticate(&s, &headers).await?,
        Principal::Device(_)
    ) {
        return Err(ApiError::Forbidden);
    }
    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or(ApiError::Unauthorized)?;
    s.store.revoke_account_token(&digest(token)).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub(crate) struct DeleteAccount {
    password: String,
}

pub(crate) async fn delete_account(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<DeleteAccount>,
) -> Result<StatusCode, ApiError> {
    let principal = crate::auth::authenticate(&s, &headers).await?;
    let account = match principal {
        Principal::Browser(account) => {
            check_origin(&s, &headers)?;
            account
        }
        Principal::Device(account) => {
            if headers.contains_key(header::ORIGIN) || headers.contains_key(header::COOKIE) {
                return Err(ApiError::Forbidden);
            }
            account
        }
        Principal::Legacy => return Err(ApiError::Forbidden),
    };
    let verified = verify_login(
        &s,
        Login {
            email: account.email,
            password: input.password,
        },
    )
    .await?;
    if verified.id != account.id {
        return Err(ApiError::Unauthorized);
    }
    match s
        .store
        .delete_account(account.id, &verified.password_hash)
        .await?
    {
        zoop_storage::AccountDeletion::Deleted => Ok(StatusCode::NO_CONTENT),
        zoop_storage::AccountDeletion::CredentialsChanged => Err(ApiError::Unauthorized),
        zoop_storage::AccountDeletion::LastAdministrator => Err(ApiError::Conflict(
            "Assign another enabled administrator before deleting this account.".into(),
        )),
    }
}
