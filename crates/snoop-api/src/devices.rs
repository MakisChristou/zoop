use axum::{
    Json,
    extract::{Path, State},
};
use chrono::{Duration, NaiveDate};
use snoop_storage::SampleRow;

use crate::{AppState, error::ApiError};

pub(crate) async fn latest(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Result<Json<Option<SampleRow>>, ApiError> {
    Ok(Json(state.store.latest_sample(&device_id).await?))
}

/// Minute-averaged samples for one UTC calendar day.
pub(crate) async fn day(
    State(state): State<AppState>,
    Path((device_id, date)): Path<(String, NaiveDate)>,
) -> Result<Json<Vec<SampleRow>>, ApiError> {
    let start = date
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| ApiError::BadRequest("invalid date".to_owned()))?
        .and_utc();
    let end = start + Duration::days(1);
    Ok(Json(
        state.store.samples_in_range(&device_id, start, end).await?,
    ))
}
