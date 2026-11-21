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

#[derive(Debug, Deserialize)]
pub(crate) struct RecoveryHistoryQuery {
    from: NaiveDate,
    to: NaiveDate,
    #[serde(default = "default_tz")]
    tz: String,
}

pub(crate) async fn recovery_history(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Query(query): Query<RecoveryHistoryQuery>,
) -> Result<Json<Vec<zoop_core::RecoveryDay>>, ApiError> {
    validate_tz(&query.tz)?;
    if !(1900..=9999).contains(&query.from.year())
        || !(1900..=9999).contains(&query.to.year())
        || query.to < query.from
        || (query.to - query.from).num_days() > 365
    {
        return Err(ApiError::BadRequest(
            "Choose a history window of at most 366 days.".into(),
        ));
    }
    zoop_core::daily_recovery_history(&state.store, &device, query.from, query.to, &query.tz)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
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
