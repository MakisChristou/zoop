use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use snoop_analytics::ALGO_VERSION;
use snoop_storage::SleepRow;

use crate::{AppState, error::ApiError};

#[derive(Debug, Deserialize)]
pub(crate) struct SleepsQuery {
    #[serde(default = "default_limit")]
    limit: i64,
}

const fn default_limit() -> i64 {
    14
}

/// Analysed nights, newest first, for the current algorithm version.
pub(crate) async fn sleeps(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
    Query(query): Query<SleepsQuery>,
) -> Result<Json<Vec<SleepRow>>, ApiError> {
    let limit = query.limit.clamp(1, 365);
    Ok(Json(
        state
            .store
            .list_sleeps(&device_id, ALGO_VERSION, limit)
            .await?,
    ))
}
