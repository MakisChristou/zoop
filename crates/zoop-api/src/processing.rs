//! Read-only pipeline status, separate from HTTP liveness.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use zoop_core::HistoryWorker;
use zoop_storage::ProcessingStatus;
pub(crate) async fn processing(
    State(state): State<AppState>,
    Path(device): Path<String>,
) -> Result<Json<ProcessingStatus>, ApiError> {
    Ok(Json(
        state
            .store
            .processing_status(
                &device,
                zoop_proto::PROTO_VERSION,
                HistoryWorker::versions(),
            )
            .await?,
    ))
}
pub(crate) async fn ready(State(state): State<AppState>) -> StatusCode {
    match state
        .store
        .processing_status("", zoop_proto::PROTO_VERSION, HistoryWorker::versions())
        .await
    {
        Ok(s) if s.workers_healthy && !s.paused => StatusCode::OK,
        _ => StatusCode::SERVICE_UNAVAILABLE,
    }
}
