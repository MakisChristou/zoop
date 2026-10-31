use axum::{
    Json,
    extract::{Path, State},
};
use chrono::{Datelike, Utc};
use serde::Deserialize;
use snoop_analytics::energy::Sex;
use snoop_storage::{NewProfile, ProfileRow};

use crate::{
    AppState,
    error::ApiError,
    query::{default_tz, validate_tz},
};

const MIN_BIRTH_YEAR: i16 = 1900;
const WEIGHT_RANGE_KG: std::ops::RangeInclusive<f32> = 20.0..=400.0;
const HEIGHT_RANGE_CM: std::ops::RangeInclusive<f32> = 50.0..=300.0;

/// The body profile, or `null` when none has been entered.
pub(crate) async fn get_profile(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Result<Json<Option<ProfileRow>>, ApiError> {
    Ok(Json(state.store.get_profile(&device_id).await?))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProfileBody {
    sex: Option<String>,
    birth_year: Option<i16>,
    weight_kg: Option<f32>,
    height_cm: Option<f32>,
    /// IANA zone days are cut in. Defaults to UTC.
    #[serde(default = "default_tz")]
    tz: String,
}

/// Replaces the body profile. Every field is optional except the zone; calories
/// need sex, birth year and weight.
pub(crate) async fn put_profile(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
    Json(body): Json<ProfileBody>,
) -> Result<Json<ProfileRow>, ApiError> {
    if let Some(sex) = body.sex.as_deref()
        && Sex::parse(sex).is_none()
    {
        return Err(ApiError::BadRequest(
            "sex must be male or female".to_owned(),
        ));
    }
    let this_year = i16::try_from(Utc::now().year()).unwrap_or(i16::MAX);
    if body
        .birth_year
        .is_some_and(|y| y < MIN_BIRTH_YEAR || y > this_year)
    {
        return Err(ApiError::BadRequest("birth_year out of range".to_owned()));
    }
    if body
        .weight_kg
        .is_some_and(|w| !WEIGHT_RANGE_KG.contains(&w))
    {
        return Err(ApiError::BadRequest("weight_kg out of range".to_owned()));
    }
    if body
        .height_cm
        .is_some_and(|h| !HEIGHT_RANGE_CM.contains(&h))
    {
        return Err(ApiError::BadRequest("height_cm out of range".to_owned()));
    }
    validate_tz(&body.tz)?;
    if state.store.local_today(&body.tz).await.is_err() {
        return Err(ApiError::BadRequest("unknown tz".to_owned()));
    }
    state
        .store
        .upsert_profile(&NewProfile {
            device_id: &device_id,
            sex: body.sex.as_deref(),
            birth_year: body.birth_year,
            weight_kg: body.weight_kg,
            height_cm: body.height_cm,
            tz: &body.tz,
        })
        .await?;
    state
        .store
        .get_profile(&device_id)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
