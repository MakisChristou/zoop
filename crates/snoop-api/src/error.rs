use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Serialize;
use snoop_storage::StorageError;
use tracing::error;

#[derive(Debug)]
pub(crate) enum ApiError {
    Unauthorized,
    BadRequest(String),
    NotFound,
    Storage(StorageError),
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    error: ErrorDetail,
}

#[derive(Debug, Serialize)]
struct ErrorDetail {
    code: &'static str,
    message: String,
}

impl From<StorageError> for ApiError {
    fn from(error: StorageError) -> Self {
        Self::Storage(error)
    }
}

impl From<snoop_core::CoreError> for ApiError {
    fn from(error: snoop_core::CoreError) -> Self {
        match error {
            snoop_core::CoreError::Storage(source) => Self::Storage(source),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            Self::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "unauthorized",
                "missing or invalid bearer token".to_owned(),
            ),
            Self::BadRequest(message) => (StatusCode::BAD_REQUEST, "bad_request", message),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                "not_found",
                "no such resource".to_owned(),
            ),
            Self::Storage(source) => {
                error!(%source, "storage failure");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "storage_unavailable",
                    "storage unavailable".to_owned(),
                )
            }
        };
        (
            status,
            Json(ErrorBody {
                error: ErrorDetail { code, message },
            }),
        )
            .into_response()
    }
}
