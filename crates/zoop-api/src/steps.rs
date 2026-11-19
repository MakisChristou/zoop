use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::NaiveDate;
use serde::Deserialize;
use zoop_core::DaySteps;

use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};

#[derive(Debug, Deserialize)]
pub(crate) struct StepsQuery {
    /// IANA time zone the day is cut in. Defaults to UTC.
    #[serde(default = "default_tz")]
    tz: String,
}

/// Steps per local hour and walking bouts for one calendar day.
pub(crate) async fn steps(
    State(state): State<AppState>,
    Path((device_id, date)): Path<(String, NaiveDate)>,
    Query(query): Query<StepsQuery>,
) -> Result<Json<DaySteps>, ApiError> {
    validate_tz(&query.tz)?;
    Ok(Json(
        zoop_core::day_steps(&state.store, &device_id, date, &query.tz).await?,
    ))
}
