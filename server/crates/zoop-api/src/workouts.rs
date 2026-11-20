//! Effective workouts and idempotent user corrections. Legacy reads and type edits
//! use the same projection as the new editor, so old clients cannot resurrect rows.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use zoop_analytics::WORKOUT_ALGO_VERSION;
use zoop_storage::{
    CorrectionReceipt, SessionInterval, SessionRevision, WorkoutCorrection, WorkoutSession,
};

#[derive(Debug, Deserialize)]
pub(crate) struct WorkoutsQuery {
    #[serde(default = "default_limit")]
    limit: i64,
    from: Option<DateTime<Utc>>,
    to: Option<DateTime<Utc>>,
    status: Option<String>,
}
const fn default_limit() -> i64 {
    30
}

pub(crate) async fn workouts(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Query(q): Query<WorkoutsQuery>,
) -> Result<Json<Vec<WorkoutSession>>, ApiError> {
    let status = q.status.as_deref().unwrap_or("active");
    if !matches!(status, "active" | "removed") || q.from.zip(q.to).is_some_and(|(a, b)| a >= b) {
        return Err(ApiError::BadRequest(
            "Choose a valid date range and workout status.".to_owned(),
        ));
    }
    Ok(Json(
        state
            .store
            .list_sessions(&device, status, q.from, q.to, q.limit.clamp(1, 500))
            .await?,
    ))
}

pub(crate) async fn workout(
    State(state): State<AppState>,
    Path((device, id)): Path<(String, i64)>,
) -> Result<Json<WorkoutSession>, ApiError> {
    state
        .store
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
            .correct_workout(&device, &body, WORKOUT_ALGO_VERSION)
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
pub(crate) struct KindBody {
    kind: String,
}

pub(crate) async fn set_kind(
    State(state): State<AppState>,
    Path((device, id)): Path<(String, i64)>,
    Json(body): Json<KindBody>,
) -> Result<Json<WorkoutSession>, ApiError> {
    let workout = state
        .store
        .get_session(&device, id)
        .await?
        .filter(|w| w.status == "active")
        .ok_or(ApiError::NotFound)?;
    if workout.kind == body.kind {
        return Ok(Json(workout));
    }
    let command = WorkoutCorrection {
        operation_id: format!("label-{}-{}-{}", workout.id, workout.revision, body.kind),
        action: "label".to_owned(),
        targets: vec![SessionRevision {
            id: workout.id,
            revision: workout.revision,
        }],
        intervals: vec![SessionInterval {
            start_ts: workout.start_ts,
            end_ts: workout.end_ts,
            kind: body.kind,
        }],
        undo_id: None,
    };
    state
        .store
        .correct_workout(&device, &command, WORKOUT_ALGO_VERSION)
        .await?;
    state
        .store
        .get_session(&device, workout.id)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
