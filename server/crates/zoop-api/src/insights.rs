//! Authenticated, date-specific morning insights from the effective sleep history.
use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{Datelike, NaiveDate};
use serde::Deserialize;
use zoop_analytics::insights::MorningInsights;
#[derive(Debug, Deserialize)]
pub(crate) struct InsightsQuery {
    #[serde(default = "default_tz")]
    tz: String,
}
pub(crate) async fn insights(
    State(state): State<AppState>,
    Path((device, day)): Path<(String, NaiveDate)>,
    Query(query): Query<InsightsQuery>,
) -> Result<Json<MorningInsights>, ApiError> {
    validate_tz(&query.tz)?;
    if !(1900..=9999).contains(&day.year()) {
        return Err(ApiError::BadRequest("Choose a valid date.".into()));
    }
    zoop_core::morning_insights(&state.store, &device, day, &query.tz)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
