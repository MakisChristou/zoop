//! Private layouts reuse the same validated widget contract, never create a share.
use super::{Config, owner, validate};
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, State},
    http::HeaderMap,
};
use serde::Deserialize;
use serde_json::{Value, json};
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SaveLayout {
    config: Config,
    revision: i64,
}
pub(crate) async fn get_layout(
    State(s): State<AppState>,
    Path(device): Path<String>,
    h: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let account = owner(&s, &h, false).await?;
    if !s.store.owns_device(account, &device).await? {
        return Err(ApiError::NotFound);
    }
    let (config, revision) = s
        .store
        .dashboard_layout(account, &device)
        .await?
        .unwrap_or((Value::Null, 0));
    Ok(Json(json!({"config":config,"revision":revision})))
}
pub(crate) async fn save_layout(
    State(s): State<AppState>,
    Path(device): Path<String>,
    h: HeaderMap,
    Json(input): Json<SaveLayout>,
) -> Result<Json<Value>, ApiError> {
    let account = owner(&s, &h, true).await?;
    if !s.store.owns_device(account, &device).await? {
        return Err(ApiError::NotFound);
    }
    validate(&input.config)?;
    if input.revision < 0 {
        return Err(ApiError::BadRequest("Invalid layout revision.".into()));
    }
    let config = serde_json::to_value(input.config).map_err(ApiError::Projection)?;
    let revision = s
        .store
        .save_dashboard_layout(account, &device, &config, input.revision)
        .await?
        .ok_or_else(|| {
            ApiError::Conflict("This dashboard changed. Reload before editing again.".into())
        })?;
    Ok(Json(json!({"config":config,"revision":revision})))
}
