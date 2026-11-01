//! Authenticated, bounded Health export and weight-history endpoints.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{DateTime, NaiveDate, Utc};
use serde::Deserialize;
use snoop_storage::{HealthInfo, HealthPage, HealthPreparation, WeightInput, WeightReading};
#[derive(Debug, Deserialize)]
pub(crate) struct Page {
    #[serde(default)]
    cursor: i64,
    watermark: Option<i64>,
    #[serde(default)]
    snapshot: bool,
    limit: Option<i64>,
}
pub(crate) async fn info(
    State(s): State<AppState>,
    Path(d): Path<String>,
) -> Result<Json<HealthInfo>, ApiError> {
    Ok(Json(s.store.health_info(&d).await?))
}
pub(crate) async fn exports(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Query(q): Query<Page>,
) -> Result<Json<HealthPage>, ApiError> {
    Ok(Json(
        s.store
            .health_page(
                &d,
                q.cursor,
                q.watermark,
                q.snapshot,
                q.limit.unwrap_or(200),
            )
            .await?,
    ))
}
#[derive(Debug, Deserialize)]
pub(crate) struct Prepare {
    from: NaiveDate,
    to: NaiveDate,
}
pub(crate) async fn prepare(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Json(q): Json<Prepare>,
) -> Result<Json<HealthPreparation>, ApiError> {
    if (q.to - q.from).num_days() > 36600 {
        return Err(ApiError::BadRequest("Choose a smaller date range.".into()));
    }
    Ok(Json(s.store.prepare_health_steps(&d, q.from, q.to).await?))
}
#[derive(Debug, Deserialize)]
pub(crate) struct WeightQuery {
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    #[serde(default)]
    after: String,
}
pub(crate) async fn weights(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Query(q): Query<WeightQuery>,
) -> Result<Json<Vec<WeightReading>>, ApiError> {
    if q.from >= q.to {
        return Err(ApiError::BadRequest(
            "Choose an end after the start.".into(),
        ));
    }
    Ok(Json(s.store.weights(&d, q.from, q.to, &q.after).await?))
}
pub(crate) async fn save_weight(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Json(w): Json<WeightInput>,
) -> Result<Json<WeightReading>, ApiError> {
    Ok(Json(s.store.save_weight(&d, &w).await?))
}
#[derive(Debug, Deserialize)]
pub(crate) struct Removed {
    ids: Vec<String>,
}
pub(crate) async fn remove_imports(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Json(q): Json<Removed>,
) -> Result<Json<bool>, ApiError> {
    s.store.remove_imported_weights(&d, &q.ids).await?;
    Ok(Json(true))
}
