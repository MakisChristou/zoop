//! Sleep display preferences; never alter measured sleep or recovery.
use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};
use axum::{
    Json,
    extract::{Path, State},
};
use serde::Deserialize;
use zoop_storage::SleepGoal;

#[derive(Debug, Deserialize)]
pub(crate) struct Input {
    minutes: i32,
    #[serde(default)]
    initialize_only: bool,
    #[serde(default = "default_tz")]
    tz: String,
}

pub(crate) async fn get(
    State(s): State<AppState>,
    Path(device): Path<String>,
) -> Result<Json<SleepGoal>, ApiError> {
    Ok(Json(s.store.sleep_goal(&device).await?))
}
pub(crate) async fn put(
    State(s): State<AppState>,
    Path(device): Path<String>,
    Json(body): Json<Input>,
) -> Result<Json<SleepGoal>, ApiError> {
    if !(60..=1440).contains(&body.minutes) || body.minutes % 15 != 0 {
        return Err(ApiError::BadRequest(
            "minutes must be 60–1440 in 15-minute steps".into(),
        ));
    }
    validate_tz(&body.tz)?;
    if s.store.local_today(&body.tz).await.is_err() {
        return Err(ApiError::BadRequest("unknown tz".into()));
    }
    Ok(Json(
        s.store
            .save_sleep_goal(&device, body.minutes, body.initialize_only, &body.tz)
            .await?,
    ))
}
