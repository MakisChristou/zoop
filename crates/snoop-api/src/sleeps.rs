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
    #[serde(default)]
    summary: bool,
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
    let nights = if query.summary {
        state
            .store
            .list_sleep_summaries(&device_id, ALGO_VERSION, limit)
            .await?
    } else {
        state
            .store
            .list_sleeps(&device_id, ALGO_VERSION, limit)
            .await?
    };
    Ok(Json(nights))
}
