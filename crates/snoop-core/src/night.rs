//! Nightly sleep analysis worker and the on-demand entry point behind `snoop analyze`.
//!
//! A "night of D" is analysed over the window from 15:00 UTC on D-1 to 11:00 UTC on D,
//! which brackets an evening-to-morning sleep for most time zones east of the Atlantic.
//! The longest detected window becomes the night's main sleep; shorter ones are kept
//! as naps in the metrics. Results are keyed by `ALGO_VERSION`, so a method change
//! produces new rows next to the old ones.

use std::time::Duration;

use chrono::{DateTime, Duration as ChronoDuration, NaiveDate, NaiveTime, Utc};
use serde::Serialize;
use snoop_analytics::ALGO_VERSION;
use snoop_analytics::sleep::{
    NightMetrics, Sample, SleepParams, SleepWindow, detect_sleep, night_metrics,
};
use snoop_analytics::stages::{StageSegment, StageSummary, stage_window};
use snoop_storage::{NewSleep, PostgresStore, SampleFull};
use tokio_util::sync::CancellationToken;
use tracing::{debug, info};

use crate::CoreResult;

const WINDOW_START_HOUR_UTC: u32 = 15;
const WINDOW_END_HOUR_UTC: u32 = 11;
/// Re-analyse this many trailing nights each pass, so late offloads are picked up.
const TRAILING_NIGHTS: i64 = 3;

/// What gets stored in `sleeps.metrics`.
#[derive(Debug, Clone, Serialize)]
pub struct NightResult {
    pub window: SleepWindow,
    pub physiology: NightMetrics,
    pub stages: StageSummary,
    pub naps: Vec<SleepWindow>,
    pub params: SleepParams,
    pub samples: usize,
}

#[derive(Debug, Clone)]
pub struct NightAnalyzer {
    store: PostgresStore,
    interval: Duration,
}

impl NightAnalyzer {
    pub const fn new(store: PostgresStore, interval: Duration) -> Self {
        Self { store, interval }
    }

    pub async fn run(self, cancel: CancellationToken) -> CoreResult<()> {
        info!(algo = ALGO_VERSION, "night analyzer running");
        loop {
            let today = Utc::now().date_naive();
            for device in self.store.list_device_ids().await? {
                for back in 0..TRAILING_NIGHTS {
                    let night = today - ChronoDuration::days(back);
                    analyze_night(&self.store, &device, night).await?;
                }
            }
            tokio::select! {
                () = cancel.cancelled() => return Ok(()),
                () = tokio::time::sleep(self.interval) => {}
            }
        }
    }
}

/// Analyses one night for one device and stores the result. Returns the main sleep
/// window when one was found.
pub async fn analyze_night(
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
        store
            .delete_sleep(device_id, night_of, ALGO_VERSION)
            .await?;
        return Ok(None);
    };
    let (segments, stage_summary): (Vec<StageSegment>, StageSummary) =
        stage_window(&samples, &main);
    let result = NightResult {
        physiology: night_metrics(&samples, &main),
        stages: stage_summary,
        naps: windows[1..].to_vec(),
        window: main,
        params,
        samples: samples.len(),
    };
    store
        .upsert_sleep(&NewSleep {
            device_id,
            night_of,
            algo_version: ALGO_VERSION,
            start_ts: result.window.onset,
            end_ts: result.window.offset,
            stages: serde_json::to_value(&segments).expect("segments serialise"),
            metrics: serde_json::to_value(&result).expect("result serialises"),
        })
        .await?;
    info!(device_id, %night_of, onset = %result.window.onset, offset = %result.window.offset,
          tib_min = result.window.time_in_bed_s / 60, "night stored");
    Ok(Some(result))
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
