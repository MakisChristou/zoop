//! Read-only summaries and explicit opt-in goal settings; no measurement mutations.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, State},
};
use chrono::Utc;
use serde::Serialize;
use snoop_storage::{WeightGoal, WeightGoalInput};

#[derive(Debug, Serialize)]
pub(crate) struct Response {
    goal: Option<WeightGoal>,
    summary: Option<snoop_core::WeightOutlook>,
}
pub(crate) async fn get(
    State(s): State<AppState>,
    Path(d): Path<String>,
) -> Result<Json<Response>, ApiError> {
    let goal = s.store.weight_goal(&d).await?;
    let mut summary = None;
    if let Some(g) = goal.as_ref().filter(|g| g.active) {
        let now = Utc::now();
        let today = s.store.weight_local_day(now, &g.timezone).await?;
        let started = s.store.weight_local_day(g.started_at, &g.timezone).await?;
        let pace = s
            .store
            .weight_local_day(g.pace_started_at, &g.timezone)
            .await?;
        let days = s.store.weight_goal_days(&d, &g.timezone, now).await?;
        summary = Some(snoop_core::weight_outlook(
            &days,
            today,
            started,
            pace,
            g.weekly_loss_kg,
        ));
    }
    Ok(Json(Response { goal, summary }))
}
pub(crate) async fn put(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Json(q): Json<WeightGoalInput>,
) -> Result<Json<WeightGoal>, ApiError> {
    Ok(Json(s.store.save_weight_goal(&d, &q).await?))
}
