//! Nightly sleep analysis worker and the on-demand entry point behind `snoop analyze`.
//!
//! Sleep is assigned to its local wake-up date. Both the CLI and leased worker
//! calculate the entire date, including naps, with persisted corrections applied.

use chrono::{DateTime, NaiveDate, Utc};
use serde::Serialize;
use snoop_analytics::ALGO_VERSION;
use snoop_analytics::sleep::{NightMetrics, Sample, SleepParams, SleepWindow, selected_window};
use snoop_analytics::stages::{EpochFeatures, StageSegment, StageSummary, features_for_window};
use snoop_storage::{PostgresStore, SampleFull};

use crate::CoreResult;

/// What gets stored in `sleeps.metrics`.
#[derive(Debug, Clone, Serialize)]
pub struct NightResult {
    pub window: SleepWindow,
    pub physiology: NightMetrics,
    pub stages: StageSummary,
    #[serde(skip)]
    pub segments: Vec<StageSegment>,
    pub naps: Vec<SleepWindow>,
    pub params: SleepParams,
    pub samples: usize,
}

/// Calculates one night without publishing; the leased worker owns publication. Returns the main sleep
/// window when one was found.
pub async fn calculate_night(
    store: &PostgresStore,
    device_id: &str,
    night_of: NaiveDate,
) -> CoreResult<Option<NightResult>> {
    let tz = store
        .get_profile(device_id)
        .await?
        .map_or_else(|| "UTC".to_owned(), |p| p.tz);
    let calculated =
        crate::sleep_sessions::calculate_sleep_day(store, device_id, night_of, &tz).await?;
    let Some(main) = calculated.iter().find(|s| s.kind == "main") else {
        return Ok(None);
    };
    let payload = main
        .metrics
        .sleep
        .clone()
        .unwrap_or(serde_json::Value::Null);
    let window: SleepWindow = serde_json::from_value(payload["window"].clone())?;
    let samples = usize::try_from(window.coverage_s).unwrap_or(0);
    let naps = calculated
        .iter()
        .filter(|s| s.kind == "nap")
        .map(|s| {
            serde_json::from_value(
                s.metrics
                    .sleep
                    .as_ref()
                    .map_or(serde_json::Value::Null, |v| v["window"].clone()),
            )
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Some(NightResult {
        window,
        physiology: serde_json::from_value(payload["physiology"].clone())?,
        stages: serde_json::from_value(payload["stages"].clone())?,
        segments: serde_json::from_value(payload["segments"].clone())?,
        naps,
        params: SleepParams::default(),
        samples,
    }))
}

/// Per-epoch features over an analysed window, recomputed from samples on demand.
pub async fn night_epochs(
    store: &PostgresStore,
    device_id: &str,
    onset: DateTime<Utc>,
    offset: DateTime<Utc>,
) -> CoreResult<Vec<EpochFeatures>> {
    let rows = store.fetch_samples(device_id, onset, offset).await?;
    let samples: Vec<Sample> = rows.iter().map(to_sample).collect();
    let window = selected_window(&samples, onset, offset);
    Ok(features_for_window(&samples, &window)
        .into_iter()
        .filter(|f| f.coverage_s > 0)
        .collect())
}

pub(crate) fn to_sample(row: &SampleFull) -> Sample {
    Sample {
        ts: row.ts,
        hr: row.hr.and_then(|h| u8::try_from(h).ok()).filter(|h| *h > 0),
        rr_ms: row
            .rr_ms
            .iter()
            .flatten()
            .filter_map(|&rr| u32::try_from(rr).ok())
            .collect(),
        motion_g: row.accel_dyn_g,
        gravity_g: match (row.gravity_x, row.gravity_y, row.gravity_z) {
            (Some(x), Some(y), Some(z)) => Some([x, y, z]),
            _ => None,
        },
        skin_temp_c: row.skin_temp_c,
        band_state: u8::try_from(row.band_state).unwrap_or(0),
        spo2_pct: row.spo2_pct.and_then(|v| u8::try_from(v).ok()),
    }
}

/// Queues one explicit night and returns its calculated preview. The worker publishes atomically.
/// # Errors
/// Database failure.
pub async fn analyze_night(
    store: &PostgresStore,
    device_id: &str,
    night_of: NaiveDate,
) -> CoreResult<Option<NightResult>> {
    let tz = store
        .get_profile(device_id)
        .await?
        .map_or_else(|| "UTC".to_owned(), |p| p.tz);
    store
        .request_analysis(device_id, "sleep", night_of, &tz, ALGO_VERSION, true)
        .await?;
    calculate_night(store, device_id, night_of).await
}
