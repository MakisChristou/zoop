//! Goal lifecycle reads and explicitly scoped settings writes; measurements never change.
use crate::{AppState, error::ApiError};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use zoop_storage::{GoalPeriod, WeightGoal, WeightGoalInput};

#[derive(Debug, Serialize)]
pub(crate) struct Response {
    goal: Option<WeightGoal>,
    summary: Option<zoop_core::WeightOutlook>,
}
pub(crate) async fn summary(
    s: &AppState,
    d: &str,
    g: &WeightGoal,
    now: DateTime<Utc>,
) -> Result<zoop_core::WeightOutlook, ApiError> {
    Ok(zoop_core::goal_outlook(&s.store, d, g, now).await?)
}

pub(crate) async fn get(
    State(s): State<AppState>,
    Path(d): Path<String>,
) -> Result<Json<Response>, ApiError> {
    let goal = s.store.weight_goal(&d).await?;
    let summary = if let Some(g) = goal.as_ref().filter(|g| g.active) {
        Some(summary(&s, &d, g, Utc::now()).await?)
    } else {
        None
    };
    Ok(Json(Response { goal, summary }))
}
pub(crate) async fn put(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Json(q): Json<WeightGoalInput>,
) -> Result<Json<WeightGoal>, ApiError> {
    Ok(Json(s.store.save_weight_goal(&d, &q).await?))
}
#[derive(Debug, Deserialize)]
pub(crate) struct HistoryQuery {
    before: Option<i64>,
    limit: Option<i64>,
}
#[derive(Debug, Serialize)]
pub(crate) struct PeriodResponse {
    id: i64,
    goal: WeightGoal,
    ended_at: DateTime<Utc>,
    end_reason: String,
    summary: zoop_core::WeightOutlook,
}
#[derive(Debug, Serialize)]
pub(crate) struct HistoryResponse {
    items: Vec<PeriodResponse>,
    next_cursor: Option<i64>,
}
async fn period_response(
    s: &AppState,
    d: &str,
    p: GoalPeriod,
    compact: bool,
) -> Result<PeriodResponse, ApiError> {
    let mut outlook = summary(s, d, &p.settings, p.ended_at - Duration::microseconds(1)).await?;
    if let Some(progress) = outlook.progress.as_mut() {
        progress.target_weight_kg = p.target_weight_kg;
        progress.completed = true;
        progress.weeks_remaining = Some(0);
        if compact {
            progress.weigh_ins.clear();
        }
    }
    if compact {
        outlook.weeks.clear();
    }
    Ok(PeriodResponse {
        id: p.id,
        goal: p.settings.0,
        ended_at: p.ended_at,
        end_reason: p.end_reason,
        summary: outlook,
    })
}
pub(crate) async fn history(
    State(s): State<AppState>,
    Path(d): Path<String>,
    Query(q): Query<HistoryQuery>,
) -> Result<Json<HistoryResponse>, ApiError> {
    let limit = q.limit.unwrap_or(20);
    if !(1..=50).contains(&limit) {
        return Err(ApiError::BadRequest(
            "Choose a history limit between 1 and 50.".into(),
        ));
    }
    let mut periods = s.store.goal_history(&d, q.before, limit + 1).await?;
    let more = periods.len() > limit as usize;
    periods.truncate(limit as usize);
    let next_cursor = if more {
        periods.last().map(|p| p.id)
    } else {
        None
    };
    let mut items = Vec::with_capacity(periods.len());
    for p in periods {
        items.push(period_response(&s, &d, p, true).await?);
    }
    Ok(Json(HistoryResponse { items, next_cursor }))
}
pub(crate) async fn detail(
    State(s): State<AppState>,
    Path((d, id)): Path<(String, i64)>,
) -> Result<Json<PeriodResponse>, ApiError> {
    let period = s.store.goal_period(&d, id).await?;
    Ok(Json(period_response(&s, &d, period, false).await?))
}
