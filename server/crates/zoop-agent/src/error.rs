//! Safe errors: never include query results, credentials or database details.
use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;
/// Agent boundary error.
#[derive(Debug, thiserror::Error)]
pub enum AgentError {
    /// Authentication failed.
    #[error("Sign in again.")]
    Unauthorized,
    /// The credential does not permit this operation.
    #[error("Access not allowed.")]
    Forbidden,
    /// Additional explicitly consented read permission is required.
    #[error("This connection does not include {0}.")]
    InsufficientScope(&'static str),
    /// No owned resource exists.
    #[error("Connection not found.")]
    NotFound,
    /// Invalid bounded request.
    #[error("{0}")]
    Invalid(&'static str),
    /// Limit exceeded.
    #[error("Too many requests. Try again shortly.")]
    Limited,
    /// Backend failure, deliberately redacted.
    #[error("Agent access is unavailable. Try again.")]
    Unavailable,
}
/// Result at the integration boundary.
pub type AgentResult<T> = Result<T, AgentError>;
impl From<zoop_storage::StorageError> for AgentError {
    fn from(error: zoop_storage::StorageError) -> Self {
        match error {
            zoop_storage::StorageError::InvalidQuery(message)
                if message == "Choose a shorter period." =>
            {
                Self::Invalid("Choose a shorter period.")
            }
            zoop_storage::StorageError::InvalidQuery(message)
                if message == "Revoke an existing connection first." =>
            {
                Self::Invalid("Revoke an existing connection first.")
            }
            _ => Self::Unavailable,
        }
    }
}
impl From<zoop_core::CoreError> for AgentError {
    fn from(_: zoop_core::CoreError) -> Self {
        Self::Unavailable
    }
}
impl IntoResponse for AgentError {
    fn into_response(self) -> Response {
        let status = match self {
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
            Self::Forbidden | Self::InsufficientScope(_) => StatusCode::FORBIDDEN,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::Invalid(_) => StatusCode::BAD_REQUEST,
            Self::Limited => StatusCode::TOO_MANY_REQUESTS,
            Self::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
        };
        let mut response =
            (status, Json(json!({"error":{"message":self.to_string()}}))).into_response();
        if let Self::InsufficientScope(scope) = self
            && let Ok(value) =
                format!("Bearer error=\"insufficient_scope\", scope=\"{scope}\"").parse()
        {
            response
                .headers_mut()
                .insert(axum::http::header::WWW_AUTHENTICATE, value);
        }
        response
    }
}
