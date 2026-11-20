//! Explicitly selected public data; sharing never grants access to private endpoints.
use crate::{AppState, auth::Principal, error::ApiError, query::validate_tz, web::check_origin};
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
};
use base64::Engine;
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use zoop_auth::{digest, hash_password, random_token, verify_password};
use zoop_storage::SharedDashboard;
mod layout;
const WIDGETS: [&str; 12] = [
    "sleep",
    "recovery",
    "load",
    "steps",
    "workouts",
    "weight",
    "hrv",
    "resting_hr",
    "activity_heatmap",
    "recent_workouts",
    "by_sport",
    "daily_rings",
];
const MAX_HISTORY_DAYS: i64 = 365;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Config {
    title: String,
    #[serde(default)]
    display_name: String,
    #[serde(default)]
    show_photo: bool,
    #[serde(default = "default_range")]
    range: String,
    #[serde(default)]
    from: Option<NaiveDate>,
    #[serde(default)]
    to: Option<NaiveDate>,
    widgets: Vec<String>,
    #[serde(default)]
    layout: Vec<layout::Placement>,
    #[serde(default)]
    heatmap_year: bool,
}
fn default_range() -> String {
    "last30".into()
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Save {
    device_id: String,
    config: Config,
    #[serde(default)]
    password: Option<String>,
    #[serde(default = "yes")]
    enabled: bool,
    #[serde(default = "default_expiry")]
    expires_at: Option<DateTime<Utc>>,
    #[serde(default)]
    revision: i64,
}
fn yes() -> bool {
    true
}
fn default_expiry() -> Option<DateTime<Utc>> {
    Some(Utc::now() + Duration::days(7))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Visit {
    token: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    year: Option<i32>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Preview {
    device_id: String,
    config: Config,
    #[serde(default)]
    year: Option<i32>,
}
fn validate(config: &Config) -> Result<(), ApiError> {
    if !layout::valid(&config.layout, &config.widgets) {
        return Err(ApiError::BadRequest(
            "Choose a layout without overlapping widgets.".into(),
        ));
    }
    if config.title.trim().is_empty()
        || config.title.len() > 80
        || config.display_name.len() > 80
        || config.widgets.is_empty()
        || config.widgets.len() > WIDGETS.len()
        || config
            .widgets
            .iter()
            .any(|w| !WIDGETS.contains(&w.as_str()))
        || config
            .widgets
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != config.widgets.len()
    {
        return Err(ApiError::BadRequest(
            "Choose a name and at least one distinct widget.".into(),
        ));
    }
    if !["last30", "all", "fixed"].contains(&config.range.as_str()) {
        return Err(ApiError::BadRequest("Choose a valid history range.".into()));
    }
    if config.range == "fixed"
        && !matches!((config.from,config.to),(Some(a),Some(b)) if a<=b && a.year()>=1900 && b.year()<=9999)
    {
        return Err(ApiError::BadRequest(
            "Choose valid start and end dates.".into(),
        ));
    }
    Ok(())
}
async fn owner(s: &AppState, h: &HeaderMap, write: bool) -> Result<i64, ApiError> {
    if write {
        check_origin(s, h)?;
    }
    match crate::auth::authenticate(s, h).await? {
        Principal::Browser(a) => Ok(a.id),
        _ => Err(ApiError::Forbidden),
    }
}
fn owned_json(row: &SharedDashboard) -> Value {
    json!({"id":row.id,"device_id":row.device_id,"token":row.token,"config":row.config,"enabled":row.enabled,"expires_at":row.expires_at,"revision":row.revision,"password_protected":row.password_hash.is_some()})
}
pub(crate) async fn list(State(s): State<AppState>, h: HeaderMap) -> Result<Json<Value>, ApiError> {
    let id = owner(&s, &h, false).await?;
    Ok(Json(json!(
        s.store
            .shared_dashboards(id)
            .await?
            .iter()
            .map(owned_json)
            .collect::<Vec<_>>()
    )))
}
async fn password(
    s: &AppState,
    value: Option<String>,
    old: Option<String>,
) -> Result<Option<String>, ApiError> {
    match value {
        None => Ok(old),
        Some(p) if p.is_empty() => Ok(None),
        Some(p) => {
            if !(8..=128).contains(&p.len()) {
                return Err(ApiError::BadRequest(
                    "Use a password between 8 and 128 characters.".into(),
                ));
            }
            let permit = s
                .password_slots
                .clone()
                .try_acquire_owned()
                .map_err(|_| ApiError::RateLimited)?;
            let hash = tokio::task::spawn_blocking(move || {
                let _permit = permit;
                hash_password(&p)
            })
            .await
            .map_err(|_| ApiError::AuthUnavailable)?
            .map_err(|_| ApiError::AuthUnavailable)?;
            Ok(Some(hash))
        }
    }
}
pub(crate) async fn create(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(input): Json<Save>,
) -> Result<Json<Value>, ApiError> {
    let account_id = owner(&s, &h, true).await?;
    validate(&input.config)?;
    if !s.store.owns_device(account_id, &input.device_id).await? {
        return Err(ApiError::NotFound);
    }
    let token = random_token().map_err(|_| ApiError::AuthUnavailable)?;
    let mut row = SharedDashboard {
        id: 0,
        account_id,
        device_id: input.device_id,
        token,
        config: serde_json::to_value(input.config).map_err(ApiError::Projection)?,
        password_hash: password(&s, input.password, None).await?,
        enabled: input.enabled,
        expires_at: input.expires_at,
        revision: 1,
    };
    row.id = s.store.create_dashboard(&row, &digest(&row.token)).await?;
    Ok(Json(owned_json(&row)))
}
pub(crate) async fn update(
    State(s): State<AppState>,
    Path(id): Path<i64>,
    h: HeaderMap,
    Json(input): Json<Save>,
) -> Result<Json<Value>, ApiError> {
    let account = owner(&s, &h, true).await?;
    validate(&input.config)?;
    let mut row = s
        .store
        .shared_dashboards(account)
        .await?
        .into_iter()
        .find(|r| r.id == id)
        .ok_or(ApiError::NotFound)?;
    if input.device_id != row.device_id {
        return Err(ApiError::BadRequest(
            "Create a separate dashboard for another device.".into(),
        ));
    }
    row.config = serde_json::to_value(input.config).map_err(ApiError::Projection)?;
    row.password_hash = password(&s, input.password, row.password_hash).await?;
    row.enabled = input.enabled;
    row.expires_at = input.expires_at;
    row.revision = input.revision;
    if !s.store.update_dashboard(&row).await? {
        return Err(ApiError::Conflict(
            "This share changed. Reload and try again.".into(),
        ));
    }
    row.revision += 1;
    Ok(Json(owned_json(&row)))
}
pub(crate) async fn remove(
    State(s): State<AppState>,
    Path(id): Path<i64>,
    h: HeaderMap,
) -> Result<StatusCode, ApiError> {
    let account = owner(&s, &h, true).await?;
    if !s.store.delete_dashboard(account, id).await? {
        return Err(ApiError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}
pub(crate) async fn preview(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(input): Json<Preview>,
) -> Result<Json<Value>, ApiError> {
    let account = owner(&s, &h, true).await?;
    validate(&input.config)?;
    if !s.store.owns_device(account, &input.device_id).await? {
        return Err(ApiError::NotFound);
    }
    let _permit = s
        .share_slots
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::RateLimited)?;
    Ok(Json(
        project(&s, &input.device_id, &input.config, input.year).await?,
    ))
}
pub(crate) async fn visit(
    State(s): State<AppState>,
    Json(input): Json<Visit>,
) -> Result<Json<Value>, ApiError> {
    if s.web.is_none()
        || input.token.len() != 64
        || !input.token.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(ApiError::NotFound);
    }
    if input.password.len() > 128 {
        return Err(ApiError::Unauthorized);
    }
    if !s.store.allow_login("share-global", 120, 60).await? {
        return Err(ApiError::RateLimited);
    }
    let hash = digest(&input.token);
    let row = s
        .store
        .public_dashboard(&hash)
        .await?
        .ok_or(ApiError::NotFound)?;
    if !s
        .store
        .allow_login(&format!("share:{}", row.id), 30, 60)
        .await?
    {
        return Err(ApiError::RateLimited);
    }
    if let Some(stored) = row.password_hash.clone() {
        let permit = s
            .password_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| ApiError::RateLimited)?;
        let valid = tokio::task::spawn_blocking(move || {
            let _permit = permit;
            verify_password(&input.password, &stored)
        })
        .await
        .map_err(|_| ApiError::AuthUnavailable)?;
        if !valid {
            return Err(ApiError::Unauthorized);
        }
    }
    let config: Config = serde_json::from_value(row.config).map_err(ApiError::Projection)?;
    validate(&config)?;
    let _permit = s
        .share_slots
        .clone()
        .try_acquire_owned()
        .map_err(|_| ApiError::RateLimited)?;
    let data = project(&s, &row.device_id, &config, input.year).await?;
    // A concurrent revoke, password/scope edit or device transfer invalidates this response.
    if !s
        .store
        .public_dashboard(&hash)
        .await?
        .is_some_and(|r| r.revision == row.revision)
    {
        return Err(ApiError::NotFound);
    }
    Ok(Json(data))
}
fn window(
    config: &Config,
    today: NaiveDate,
    earliest: NaiveDate,
    year: Option<i32>,
) -> Result<(NaiveDate, NaiveDate), ApiError> {
    let (start, end) = match config.range.as_str() {
        "last30" => (today - Duration::days(29), today),
        "fixed" => (
            config.from.ok_or(ApiError::NotFound)?,
            config.to.ok_or(ApiError::NotFound)?.min(today),
        ),
        _ => (earliest.min(today), today),
    };
    if start > end {
        return Err(ApiError::BadRequest(
            "This period has not started yet.".into(),
        ));
    }
    if config.range == "last30" || (end - start).num_days() <= MAX_HISTORY_DAYS {
        return Ok((start, end));
    }
    let year = year.unwrap_or(end.year());
    let a = NaiveDate::from_ymd_opt(year, 1, 1)
        .filter(|_| (1900..=9999).contains(&year))
        .ok_or_else(|| ApiError::BadRequest("Choose a valid year.".into()))?;
    let b = NaiveDate::from_ymd_opt(year, 12, 31).ok_or(ApiError::NotFound)?;
    if b < start || a > end {
        return Err(ApiError::NotFound);
    }
    Ok((a.max(start), b.min(end)))
}
async fn project(
    s: &AppState,
    device: &str,
    config: &Config,
    year: Option<i32>,
) -> Result<Value, ApiError> {
    let tz = s
        .store
        .get_profile(device)
        .await?
        .map_or_else(|| "UTC".into(), |p| p.tz);
    validate_tz(&tz)?;
    let today = s.store.local_today(&tz).await?;
    let earliest = s
        .store
        .shared_earliest(device, &tz, &config.widgets)
        .await?
        .unwrap_or(today)
        .min(today);
    let (from, to) = window(config, today, earliest, year)?;
    let mut widgets = Vec::new();
    for key in &config.widgets {
        match key.as_str() {
            "daily_rings" => {
                // One date for all three readings. Never substitute older non-null values.
                let sleep = s
                    .store
                    .shared_points(device, &tz, to, to, "sleep", zoop_analytics::ALGO_VERSION)
                    .await?;
                let load = s
                    .store
                    .shared_points(
                        device,
                        &tz,
                        to,
                        to,
                        "load",
                        zoop_analytics::WORKOUT_ALGO_VERSION,
                    )
                    .await?;
                let brief = zoop_core::morning_insights(&s.store, device, to, &tz).await?;
                let recovery = brief.map(|b| json!({"version":b.recovery.version,"method":b.recovery.method,"score":b.recovery.score,"band":b.recovery.band,"state":b.recovery.state}));
                widgets.push(json!({"key":key,"day":to,"sleep_seconds":sleep.first().and_then(|p| p.get("value")),"load":load.first().and_then(|p|p.get("value")),"recovery":recovery}));
                continue;
            }
            "activity_heatmap" => {
                let heatmap_from = if config.heatmap_year {
                    to - Duration::days(364)
                } else {
                    from
                };
                let points = s
                    .store
                    .shared_points(
                        device,
                        &tz,
                        heatmap_from,
                        to,
                        "load",
                        zoop_analytics::WORKOUT_ALGO_VERSION,
                    )
                    .await?;
                let activities = s
                    .store
                    .shared_activity_days(device, &tz, heatmap_from, to)
                    .await?;
                widgets.push(json!({"key":key,"from":heatmap_from,"to":to,"points":points,"activities":activities}));
                continue;
            }
            "recent_workouts" => {
                let activities = s.store.shared_activities(device, &tz, from, to).await?;
                widgets.push(json!({"key":key,"activities":activities}));
                continue;
            }
            "by_sport" => {
                let sports = s.store.shared_sports(device, &tz, from, to).await?;
                widgets.push(json!({"key":key,"sports":sports}));
                continue;
            }
            _ => {}
        }
        let version = if ["sleep", "hrv", "resting_hr"].contains(&key.as_str()) {
            zoop_analytics::ALGO_VERSION
        } else {
            zoop_analytics::WORKOUT_ALGO_VERSION
        };
        let points = if key == "recovery" {
            zoop_core::recovery_history(&s.store, device, from, to, &tz).await?
        } else {
            s.store
                .shared_points(device, &tz, from, to, key, version)
                .await?
        };
        widgets.push(json!({"key":key,"points":points}));
    }
    let photo = if config.show_photo {
        s.store.profile_photo(device).await?.map(|bytes| {
            format!(
                "data:image/jpeg;base64,{}",
                base64::engine::general_purpose::STANDARD.encode(bytes)
            )
        })
    } else {
        None
    };
    let lower = match config.range.as_str() {
        "last30" => from,
        "fixed" => config.from.unwrap_or(from),
        _ => earliest,
    };
    let upper = if config.range == "fixed" {
        config.to.unwrap_or(today).min(today)
    } else {
        today
    };
    Ok(
        json!({"title":config.title,"display_name":config.display_name,"photo":photo,"timezone":tz,"from":from,"to":to,"paged":config.range!="last30" && (upper-lower).num_days()>MAX_HISTORY_DAYS,"first_year":lower.year(),"last_year":upper.year(),"widgets":widgets,"layout":config.layout}),
    )
}

#[cfg(test)]
mod tests;
