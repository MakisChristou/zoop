use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::NaiveDate;
use serde::Deserialize;
use zoop_storage::{MinuteRow, SampleRow};

use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};

pub(crate) async fn latest(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Result<Json<Option<SampleRow>>, ApiError> {
    Ok(Json(state.store.latest_sample(&device_id).await?))
}

#[derive(Debug, Deserialize)]
pub(crate) struct DayQuery {
    /// IANA time zone the day is cut in. Defaults to UTC.
    #[serde(default = "default_tz")]
    tz: String,
}

/// Minute buckets for one local calendar day: heart rate, skin temperature, steps,
/// the strap's state and activity labels, SpO₂.
pub(crate) async fn day(
    State(state): State<AppState>,
    Path((device_id, date)): Path<(String, NaiveDate)>,
    Query(query): Query<DayQuery>,
) -> Result<Json<Vec<MinuteRow>>, ApiError> {
    validate_tz(&query.tz)?;
    Ok(Json(
        state
            .store
            .minutes_for_local_day(&device_id, date, &query.tz)
            .await?,
    ))
}
