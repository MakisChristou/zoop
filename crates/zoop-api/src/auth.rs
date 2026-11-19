use axum::{
    extract::{Request, State},
    http::header,
    middleware::Next,
    response::Response,
};
use secrecy::ExposeSecret;

use crate::{AppState, error::ApiError};
use axum::{
    RequestExt,
    extract::RawPathParams,
    http::{HeaderMap, Method},
};
use zoop_auth::digest;
use zoop_storage::Account;

#[derive(Debug, Clone)]
pub(crate) enum Principal {
    Legacy,
    Device(Account),
    Browser(Account),
}

pub(crate) fn session_token(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(header::COOKIE)?
        .to_str()
        .ok()?
        .split(';')
        .map(str::trim)
        .find_map(|s| s.strip_prefix("zoop_session="))
        .filter(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit()))
}
pub(crate) async fn authenticate(
    state: &AppState,
    headers: &HeaderMap,
) -> Result<Principal, ApiError> {
    if state.web.is_none() {
        return Err(ApiError::NotFound);
    }
    if let Some(bearer) = headers.get(header::AUTHORIZATION) {
        let token = bearer
            .to_str()
            .ok()
            .and_then(|s| s.strip_prefix(BEARER_PREFIX))
            .filter(|s| s.len() <= 512)
            .ok_or(ApiError::Unauthorized)?;
        return state
            .store
            .token_account(&digest(token))
            .await?
            .map(Principal::Device)
            .ok_or(ApiError::Unauthorized);
    }
    let token = session_token(headers).ok_or(ApiError::Unauthorized)?;
    state
        .store
        .session_account(&digest(token))
        .await?
        .map(Principal::Browser)
        .ok_or(ApiError::Unauthorized)
}

const BEARER_PREFIX: &str = "Bearer ";

pub(crate) async fn require_bearer(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> Result<Response, ApiError> {
    if state.web.is_some() {
        let principal = authenticate(&state, request.headers()).await?;
        if matches!(principal, Principal::Browser(_))
            && request.method() != Method::GET
            && request.method() != Method::HEAD
        {
            return Err(ApiError::Forbidden);
        }
        if request.uri().path() != "/v1/ingest" && request.uri().path() != "/v2/ingest" {
            let params = request
                .extract_parts::<RawPathParams>()
                .await
                .map_err(|_| ApiError::BadRequest("invalid route parameters".into()))?;
            {
                let (_, device) = params
                    .iter()
                    .find(|(key, _)| *key == "deviceId")
                    .ok_or(ApiError::Forbidden)?;
                let id = match &principal {
                    Principal::Browser(a) | Principal::Device(a) => a.id,
                    Principal::Legacy => return Err(ApiError::Forbidden),
                };
                if !state.store.owns_device(id, device).await? {
                    return Err(ApiError::NotFound);
                }
            }
        }
        request.extensions_mut().insert(principal);
        return Ok(next.run(request).await);
    }
    let presented = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix(BEARER_PREFIX));

    match presented {
        Some(token) if constant_time_eq(token, state.ingest_token.expose_secret()) => {
            request.extensions_mut().insert(Principal::Legacy);
            Ok(next.run(request).await)
        }
        _ => Err(ApiError::Unauthorized),
    }
}

/// Length-independent comparison so timing does not leak how many bytes matched.
fn constant_time_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    let mut diff = u8::from(a.len() != b.len());
    for (x, y) in a.iter().zip(b.iter().cycle()) {
        diff |= x ^ y;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::constant_time_eq;

    #[test]
    fn compares_exactly() {
        assert!(constant_time_eq("abc", "abc"));
        assert!(!constant_time_eq("abc", "abd"));
        assert!(!constant_time_eq("abc", "abcd"));
        assert!(!constant_time_eq("", "a"));
    }
}
