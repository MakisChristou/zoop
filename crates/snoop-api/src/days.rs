use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use snoop_storage::DayRow;

use crate::{AppState, error::ApiError};

#[derive(Debug, Deserialize)]
pub(crate) struct DaysQuery {
    #[serde(default = "default_limit")]
    limit: i64,
    /// IANA time zone used to cut days at local midnight. Defaults to UTC.
    #[serde(default = "default_tz")]
    tz: String,
}

const fn default_limit() -> i64 {
    14
}

fn default_tz() -> String {
    "UTC".to_owned()
}

/// Daily summaries, oldest first.
pub(crate) async fn days(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
    Query(query): Query<DaysQuery>,
) -> Result<Json<Vec<DayRow>>, ApiError> {
    if query.tz.len() > 64
        || !query
            .tz
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "/_+-".contains(c))
    {
        return Err(ApiError::BadRequest("invalid tz".to_owned()));
    }
    let limit = query.limit.clamp(1, 366);
    Ok(Json(
        state.store.list_days(&device_id, &query.tz, limit).await?,
    ))
}
