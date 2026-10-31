use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use snoop_analytics::WORKOUT_ALGO_VERSION;
use snoop_analytics::workouts::WorkoutKind;
use snoop_storage::WorkoutRow;

use crate::{AppState, error::ApiError};

#[derive(Debug, Deserialize)]
pub(crate) struct WorkoutsQuery {
    #[serde(default = "default_limit")]
    limit: i64,
}

const fn default_limit() -> i64 {
    30
}

/// Detected sessions, newest first, for the current algorithm version, with the
/// user's label applied where one exists.
pub(crate) async fn workouts(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
    Query(query): Query<WorkoutsQuery>,
) -> Result<Json<Vec<WorkoutRow>>, ApiError> {
    let limit = query.limit.clamp(1, 500);
    Ok(Json(
        state
            .store
            .list_workouts(&device_id, WORKOUT_ALGO_VERSION, limit)
            .await?,
    ))
}

#[derive(Debug, Deserialize)]
pub(crate) struct KindBody {
    kind: String,
}

/// Records the user's kind for a session and returns it updated.
pub(crate) async fn set_kind(
    State(state): State<AppState>,
    Path((device_id, id)): Path<(String, i64)>,
    Json(body): Json<KindBody>,
) -> Result<Json<WorkoutRow>, ApiError> {
    let kind = WorkoutKind::parse(&body.kind).ok_or_else(|| {
        ApiError::BadRequest("kind must be walk, resistance or activity".to_owned())
    })?;
    let workout = state
        .store
        .get_workout(&device_id, WORKOUT_ALGO_VERSION, id)
        .await?
        .ok_or(ApiError::NotFound)?;
    state
        .store
        .upsert_label(&device_id, workout.start_ts, workout.end_ts, kind.as_str())
        .await?;
    state
        .store
        .get_workout(&device_id, WORKOUT_ALGO_VERSION, id)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
