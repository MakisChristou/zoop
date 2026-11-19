use axum::{
    extract::{Request, State},
    http::header,
    middleware::Next,
    response::Response,
};
use secrecy::ExposeSecret;

use crate::{AppState, error::ApiError};

const BEARER_PREFIX: &str = "Bearer ";

pub(crate) async fn require_bearer(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, ApiError> {
    let presented = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix(BEARER_PREFIX));

    match presented {
        Some(token) if constant_time_eq(token, state.ingest_token.expose_secret()) => {
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
