//! Nightly sleep analysis worker and the on-demand entry point behind `snoop analyze`.
//!
//! A "night of D" is analysed over the window from 15:00 UTC on D-1 to 11:00 UTC on D,
//! which brackets an evening-to-morning sleep for most time zones east of the Atlantic.
//! The longest detected window becomes the night's main sleep; shorter ones are kept
//! as naps in the metrics. Results are keyed by `ALGO_VERSION`, so a method change
//! produces new rows next to the old ones.

use chrono::{DateTime, Duration as ChronoDuration, NaiveDate, NaiveTime, Utc};
use serde::Serialize;
use snoop_analytics::ALGO_VERSION;
use snoop_analytics::sleep::{
    NightMetrics, Sample, SleepParams, SleepWindow, detect_sleep, night_metrics,
};
use snoop_analytics::stages::{
    EpochFeatures, StageSegment, StageSummary, features_for_window, stage_window,
};
use snoop_storage::{PostgresStore, SampleFull};
use tracing::{debug, info};

use crate::CoreResult;

const WINDOW_START_HOUR_UTC: u32 = 15;
const WINDOW_END_HOUR_UTC: u32 = 11;

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
    let (from, to) = night_bounds(night_of);
    let rows = store.fetch_samples(device_id, from, to).await?;
    let samples: Vec<Sample> = rows.iter().map(to_sample).collect();
    let params = SleepParams::default();
    let mut windows = detect_sleep(&samples, &params);
    windows.sort_by_key(|w| std::cmp::Reverse(w.time_in_bed_s));

    let Some(main) = windows.first().cloned() else {
        debug!(device_id, %night_of, samples = samples.len(), "no sleep window");
        return Ok(None);
    };
    let (segments, stage_summary): (Vec<StageSegment>, StageSummary) =
        stage_window(&samples, &main);
    let result = NightResult {
        physiology: night_metrics(&samples, &main),
        stages: stage_summary,
        segments,
        naps: windows[1..].to_vec(),
        window: main,
        params,
        samples: samples.len(),
    };
    info!(device_id, %night_of, onset = %result.window.onset, offset = %result.window.offset,
          tib_min = result.window.time_in_bed_s / 60, "night stored");
    Ok(Some(result))
}

/// Per-epoch features over an analysed window, recomputed from samples on demand.
pub async fn night_epochs(
    store: &PostgresStore,
    device_id: &str,
    onset: DateTime<Utc>,
    offset: DateTime<Utc>,
) -> CoreResult<Vec<EpochFeatures>> {
    let rows = store
        .fetch_samples(device_id, onset, offset + ChronoDuration::seconds(1))
        .await?;
    let samples: Vec<Sample> = rows.iter().map(to_sample).collect();
    let window = SleepWindow {
        onset,
        offset,
        time_in_bed_s: (offset - onset).num_seconds() + 1,
        asleep_s: 0,
        waso_s: 0,
        efficiency: 0.0,
        coverage_s: samples.len() as i64,
        disturbances: 0,
    };
    Ok(features_for_window(&samples, &window))
}

fn night_bounds(night_of: NaiveDate) -> (DateTime<Utc>, DateTime<Utc>) {
    let start = (night_of - ChronoDuration::days(1))
        .and_time(NaiveTime::from_hms_opt(WINDOW_START_HOUR_UTC, 0, 0).expect("valid"))
        .and_utc();
    let end = night_of
        .and_time(NaiveTime::from_hms_opt(WINDOW_END_HOUR_UTC, 0, 0).expect("valid"))
        .and_utc();
    (start, end)
}

fn to_sample(row: &SampleFull) -> Sample {
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
    store
        .request_analysis(device_id, "sleep", night_of, "UTC", ALGO_VERSION, true)
        .await?;
    calculate_night(store, device_id, night_of).await
}
