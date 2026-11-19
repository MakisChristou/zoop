//! Authenticated progress summary; cut periods at local midnight, never at now.
use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use zoop_core::Progress;
#[derive(Debug, Deserialize)]
pub(crate) struct ProgressQuery {
    #[serde(default = "default_tz")]
    tz: String,
}
pub(crate) async fn progress(
    State(state): State<AppState>,
    Path(device): Path<String>,
    Query(q): Query<ProgressQuery>,
) -> Result<Json<Progress>, ApiError> {
    validate_tz(&q.tz)?;
    let today = state.store.progress_today(&q.tz).await?;
    zoop_core::progress(&state.store, &device, today, &q.tz)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
