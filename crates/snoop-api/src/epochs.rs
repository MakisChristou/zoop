use axum::{
    Json,
    extract::{Path, State},
};
use chrono::NaiveDate;
use serde::Serialize;
use snoop_analytics::ALGO_VERSION;

use crate::{AppState, error::ApiError};

/// One thirty-second epoch of a night: the features the stager saw.
#[derive(Debug, Serialize)]
pub(crate) struct EpochOut {
    pub start: chrono::DateTime<chrono::Utc>,
    pub hr: Option<f64>,
    pub hr_variability: Option<f64>,
    pub rmssd: Option<f64>,
    pub resp_rate: Option<f64>,
    pub move_frac: f64,
    pub strap_awake: bool,
}

/// Per-epoch physiology for an analysed night, aligned with its stage segments.
pub(crate) async fn epochs(
    State(state): State<AppState>,
    Path((device_id, night_of)): Path<(String, NaiveDate)>,
) -> Result<Json<Vec<EpochOut>>, ApiError> {
    let Some(sleep) = state
        .store
        .get_sleep(&device_id, night_of, ALGO_VERSION)
        .await?
    else {
        return Ok(Json(Vec::new()));
    };
    let features =
        snoop_core::night_epochs(&state.store, &device_id, sleep.start_ts, sleep.end_ts).await?;
    Ok(Json(features.into_iter().map(EpochOut::from).collect()))
}

impl From<snoop_analytics::stages::EpochFeatures> for EpochOut {
    fn from(f: snoop_analytics::stages::EpochFeatures) -> Self {
        Self {
            start: f.start,
            hr: if f.hr_coverage_s > 0 { f.hr_mean } else { None },
            hr_variability: if f.hr_coverage_s > 0 { f.hr_dog } else { None },
            rmssd: if f.coverage_s > 0 { f.rmssd } else { None },
            resp_rate: if f.coverage_s > 0 { f.resp_rate } else { None },
            move_frac: f.move_frac,
            strap_awake: f.strap_awake,
        }
    }
}
