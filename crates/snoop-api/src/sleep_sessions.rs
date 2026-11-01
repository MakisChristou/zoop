//! Stable sleep records and the same correction commands used by workouts.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use snoop_storage::{
    CorrectionReceipt, ResetCommand, ResetPreview, ResetReceipt, ResetScope, SessionDomain,
    UndoReset, WorkoutCorrection, WorkoutSession,
};
#[derive(Debug, Deserialize)]
pub(crate) struct QueryArgs {
    from: Option<DateTime<Utc>>,
    to: Option<DateTime<Utc>>,
    status: Option<String>,
    limit: Option<i64>,
}
pub(crate) async fn list(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Query(q): Query<QueryArgs>,
) -> Result<Json<Vec<WorkoutSession>>, ApiError> {
    let status = q.status.as_deref().unwrap_or("active");
    if !matches!(status, "active" | "removed") || q.from.zip(q.to).is_some_and(|(a, b)| a >= b) {
        return Err(ApiError::BadRequest("Choose a valid date range.".into()));
    }
    Ok(Json(
        state
            .store
            .sessions(SessionDomain::Sleep)
            .list_sessions(
                &device,
                status,
                q.from,
                q.to,
                q.limit.unwrap_or(365).clamp(1, 1000),
            )
            .await?,
    ))
}
pub(crate) async fn get(
    State(state): State<AppState>,
    Path((device, id)): Path<(String, i64)>,
) -> Result<Json<WorkoutSession>, ApiError> {
    state
        .store
        .sessions(SessionDomain::Sleep)
        .get_session(&device, id)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
pub(crate) async fn correct(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Json(body): Json<WorkoutCorrection>,
) -> Result<Json<CorrectionReceipt>, ApiError> {
    Ok(Json(
        state
            .store
            .sessions(SessionDomain::Sleep)
            .correct_workout(&device, &body, snoop_analytics::ALGO_VERSION)
            .await?,
    ))
}
pub(crate) async fn epochs(
    State(state): State<AppState>,
    Path((device, id)): Path<(String, i64)>,
) -> Result<Json<Vec<crate::epochs::EpochOut>>, ApiError> {
    let row = state
        .store
        .sessions(SessionDomain::Sleep)
        .get_session(&device, id)
        .await?
        .ok_or(ApiError::NotFound)?;
    let features =
        snoop_core::night_epochs(&state.store, &device, row.start_ts, row.end_ts).await?;
    Ok(Json(
        features
            .into_iter()
            .map(crate::epochs::EpochOut::from)
            .collect(),
    ))
}
pub(crate) async fn preview_reset(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Json(scope): Json<ResetScope>,
) -> Result<Json<ResetPreview>, ApiError> {
    Ok(Json(state.store.preview_reset(&device, &scope).await?))
}
pub(crate) async fn reset(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Json(command): Json<ResetCommand>,
) -> Result<Json<ResetReceipt>, ApiError> {
    Ok(Json(
        state
            .store
            .reset_analysis(&device, &command, snoop_core::HistoryWorker::versions())
            .await?,
    ))
}
pub(crate) async fn undo_reset(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Json(command): Json<UndoReset>,
) -> Result<Json<ResetReceipt>, ApiError> {
    Ok(Json(
        state
            .store
            .undo_reset(&device, &command, snoop_core::HistoryWorker::versions())
            .await?,
    ))
}
pub(crate) async fn resets(
    State(state): State<AppState>,
    Path(device): Path<String>,
) -> Result<Json<Vec<serde_json::Value>>, ApiError> {
    Ok(Json(state.store.reset_history(&device).await?))
}
