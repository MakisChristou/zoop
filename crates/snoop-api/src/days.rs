use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use snoop_analytics::WORKOUT_ALGO_VERSION;
use snoop_storage::DayRow;

use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};

#[derive(Debug, Deserialize)]
pub(crate) struct DaysQuery {
    #[serde(default = "default_limit")]
    limit: i64,
    /// IANA time zone used to cut days at local midnight. Defaults to UTC.
    #[serde(default = "default_tz")]
    tz: String,
}

const fn default_limit() -> i64 {
    14
}

/// Daily summaries, oldest first, with the day's load where it has been analysed.
pub(crate) async fn days(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
    Query(query): Query<DaysQuery>,
) -> Result<Json<Vec<DayRow>>, ApiError> {
    validate_tz(&query.tz)?;
    let limit = query.limit.clamp(1, 366);
    Ok(Json(
        state
            .store
            .list_days(&device_id, &query.tz, limit, WORKOUT_ALGO_VERSION)
            .await?,
    ))
}
