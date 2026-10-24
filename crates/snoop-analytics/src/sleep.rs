//! Sleep window detection and per-night metrics from one-second samples.
//!
//! Window: the strap's own band state (WHOOP's on-device rest flag) is the anchor.
//! Per-second sleep flags are majority-smoothed over a centred window, nearby runs
//! are merged across short awakenings, short runs are discarded, and each candidate
//! is confirmed cardiac-wise against the day's awake heart rate. This mirrors the
//! actigraphy convention of Cole & Kripke (1992) and Sadeh (1994): a sleep/wake
//! classifier per epoch, then rules for onset and offset.
//!
//! Metrics follow AASM definitions: time in bed, total sleep time, wake after sleep
//! onset, efficiency. Resting heart rate is the lowest sustained five-minute mean.
//! HRV is the mean of five-minute RMSSD windows (Task Force 1996). Respiratory rate
//! comes from respiratory sinus arrhythmia (see `respiration`).

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::hrv;

/// One second of strap data, as stored in `samples`.
#[derive(Debug, Clone, PartialEq)]
pub struct Sample {
    pub ts: DateTime<Utc>,
    pub hr: Option<u8>,
    pub rr_ms: Vec<u32>,
    /// Dynamic acceleration in g, when the record carried one.
    pub motion_g: Option<f32>,
    pub skin_temp_c: Option<f32>,
    /// 0 wake, 1 still, 2 sleep, 3 up.
    pub band_state: u8,
    pub spo2_pct: Option<u8>,
}

impl Sample {
    pub const BAND_SLEEP: u8 = 2;
}

/// Tunables, exposed so they can be reported next to results.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct SleepParams {
    /// Centred majority-vote window over the per-second sleep flag.
    pub smooth_s: i64,
    /// Awakenings shorter than this stay inside the window, as wake after sleep onset.
    pub merge_gap_s: i64,
    /// Candidate windows shorter than this are not sleep.
    pub min_duration_s: i64,
    /// Mean HR inside the window must be below this fraction of the awake median.
    pub hr_confirm_ratio: f64,
    /// Fewer awake HR samples than this skips the cardiac check.
    pub hr_confirm_min_samples: usize,
}

impl Default for SleepParams {
    fn default() -> Self {
        Self {
            smooth_s: 300,
            merge_gap_s: 1800,
            min_duration_s: 1200,
            hr_confirm_ratio: 1.05,
            hr_confirm_min_samples: 600,
        }
    }
}

/// A detected sleep window with AASM-style accounting.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SleepWindow {
    pub onset: DateTime<Utc>,
    pub offset: DateTime<Utc>,
    /// Seconds between onset and offset.
    pub time_in_bed_s: i64,
    /// Seconds the strap flagged as sleep inside the window.
    pub asleep_s: i64,
    /// Wake after sleep onset: seconds inside the window not flagged as sleep.
    pub waso_s: i64,
    /// asleep / time in bed.
    pub efficiency: f64,
    /// Seconds of data actually present in the window (gaps reduce this).
    pub coverage_s: i64,
    /// Awakenings of at least 60 s inside the window.
    pub disturbances: u32,
}

/// Per-night physiology computed over a sleep window.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NightMetrics {
    /// Lowest sustained five-minute mean heart rate, bpm.
    pub resting_hr: Option<f64>,
    /// Mean of five-minute RMSSD windows, ms.
    pub hrv_rmssd_ms: Option<f64>,
    /// Number of five-minute windows that had enough clean beats.
    pub hrv_windows: usize,
    /// Breaths per minute, median over one-minute windows.
    pub respiratory_rate: Option<f64>,
    /// Mean skin temperature, °C.
    pub skin_temp_c: Option<f64>,
    /// Median SpO₂ over the strap's measurement windows, percent.
    pub spo2_pct: Option<f64>,
    pub spo2_windows: usize,
}

const FIVE_MINUTES_S: i64 = 300;
const ONE_MINUTE_S: i64 = 60;
const DISTURBANCE_MIN_S: i64 = 60;
const RHR_MIN_BIN_SAMPLES: usize = 150;
const RHR_MIN_PLAUSIBLE_BPM: f64 = 25.0;
const HRV_MIN_BEATS_PER_WINDOW: usize = 100;
const SPO2_WINDOW_GAP_S: i64 = 60;

/// Finds sleep windows in a day's worth of samples (sorted by time, one per second).
pub fn detect_sleep(samples: &[Sample], params: &SleepParams) -> Vec<SleepWindow> {
    if samples.is_empty() {
        return Vec::new();
    }
    let flags: Vec<bool> = samples
        .iter()
        .map(|s| s.band_state == Sample::BAND_SLEEP)
        .collect();
    let smoothed = majority_smooth(samples, &flags, params.smooth_s);

    // Runs of smoothed sleep, merged across gaps shorter than merge_gap_s.
    let mut runs: Vec<(usize, usize)> = Vec::new();
    for (i, &asleep) in smoothed.iter().enumerate() {
        if !asleep {
            continue;
        }
        match runs.last_mut() {
            Some(last)
                if (samples[i].ts - samples[last.1].ts).num_seconds() <= params.merge_gap_s =>
            {
                last.1 = i;
            }
            _ => runs.push((i, i)),
        }
    }

    let awake_median_hr = awake_median_hr(samples, &smoothed);

    runs.into_iter()
        .filter_map(|(start, end)| {
            let duration = (samples[end].ts - samples[start].ts).num_seconds() + 1;
            if duration < params.min_duration_s {
                return None;
            }
            let inside = &samples[start..=end];
            if let Some(median) = awake_median_hr {
                let hrs: Vec<f64> = inside.iter().filter_map(|s| s.hr).map(f64::from).collect();
                if hrs.len() >= params.hr_confirm_min_samples {
                    let mean = hrs.iter().sum::<f64>() / hrs.len() as f64;
                    if mean > median * params.hr_confirm_ratio {
                        return None;
                    }
                }
            }
            Some(account(inside))
        })
        .collect()
}

fn account(inside: &[Sample]) -> SleepWindow {
    let onset = inside[0].ts;
    let offset = inside[inside.len() - 1].ts;
    let time_in_bed_s = (offset - onset).num_seconds() + 1;
    let asleep_s = inside
        .iter()
        .filter(|s| s.band_state == Sample::BAND_SLEEP)
        .count() as i64;
    let coverage_s = inside.len() as i64;
    let waso_s = coverage_s - asleep_s;

    let mut disturbances = 0;
    let mut awake_run_start: Option<DateTime<Utc>> = None;
    for s in inside {
        if s.band_state == Sample::BAND_SLEEP {
            if let Some(start) = awake_run_start.take()
                && (s.ts - start).num_seconds() >= DISTURBANCE_MIN_S
            {
                disturbances += 1;
            }
        } else if awake_run_start.is_none() {
            awake_run_start = Some(s.ts);
        }
    }

    SleepWindow {
        onset,
        offset,
        time_in_bed_s,
        asleep_s,
        waso_s,
        efficiency: if time_in_bed_s > 0 {
            asleep_s as f64 / time_in_bed_s as f64
        } else {
            0.0
        },
        coverage_s,
        disturbances,
    }
}

/// Majority vote over a centred time window, so data gaps shrink the vote rather than
/// pad it.
fn majority_smooth(samples: &[Sample], flags: &[bool], window_s: i64) -> Vec<bool> {
    let half = Duration::seconds(window_s / 2);
    let mut prefix = vec![0usize; flags.len() + 1];
    for (i, &f) in flags.iter().enumerate() {
        prefix[i + 1] = prefix[i] + usize::from(f);
    }
    let (mut lo, mut hi) = (0usize, 0usize);
    samples
        .iter()
        .map(|s| {
            while samples[lo].ts < s.ts - half {
                lo += 1;
            }
            while hi < samples.len() && samples[hi].ts <= s.ts + half {
                hi += 1;
            }
            2 * (prefix[hi] - prefix[lo]) > hi - lo
        })
        .collect()
}

fn awake_median_hr(samples: &[Sample], smoothed: &[bool]) -> Option<f64> {
    let mut hrs: Vec<f64> = samples
        .iter()
        .zip(smoothed)
        .filter(|(_, asleep)| !**asleep)
        .filter_map(|(s, _)| s.hr)
        .map(f64::from)
        .collect();
    if hrs.is_empty() {
        return None;
    }
    hrs.sort_by(|a, b| a.total_cmp(b));
    Some(hrs[hrs.len() / 2])
}

/// Computes per-night physiology over `[onset, offset]`.
pub fn night_metrics(samples: &[Sample], window: &SleepWindow) -> NightMetrics {
    let inside: Vec<&Sample> = samples
        .iter()
        .filter(|s| s.ts >= window.onset && s.ts <= window.offset)
        .collect();

    NightMetrics {
        resting_hr: resting_hr(&inside, window.onset),
        hrv_rmssd_ms: hrv_windows(&inside, window.onset).0,
        hrv_windows: hrv_windows(&inside, window.onset).1,
        respiratory_rate: respiratory_rate(&inside, window.onset),
        skin_temp_c: mean(inside.iter().filter_map(|s| s.skin_temp_c).map(f64::from)),
        spo2_pct: spo2(&inside).0,
        spo2_windows: spo2(&inside).1,
    }
}

/// Lowest mean over five-minute bins with enough samples and a plausible value.
fn resting_hr(inside: &[&Sample], onset: DateTime<Utc>) -> Option<f64> {
    bins(inside, onset, FIVE_MINUTES_S)
        .into_iter()
        .filter_map(|bin| {
            let hrs: Vec<f64> = bin.iter().filter_map(|s| s.hr).map(f64::from).collect();
            (hrs.len() >= RHR_MIN_BIN_SAMPLES)
                .then(|| hrs.iter().sum::<f64>() / hrs.len() as f64)
                .filter(|m| *m >= RHR_MIN_PLAUSIBLE_BPM)
        })
        .min_by(|a, b| a.total_cmp(b))
}

/// Mean RMSSD over five-minute windows with enough clean beats.
fn hrv_windows(inside: &[&Sample], onset: DateTime<Utc>) -> (Option<f64>, usize) {
    let values: Vec<f64> = bins(inside, onset, FIVE_MINUTES_S)
        .into_iter()
        .filter_map(|bin| {
            let rr: Vec<u32> = bin.iter().flat_map(|s| s.rr_ms.iter().copied()).collect();
            let clean = hrv::clean_rr(&rr);
            (clean.len() >= HRV_MIN_BEATS_PER_WINDOW)
                .then(|| hrv::rmssd(&clean))
                .flatten()
        })
        .collect();
    (mean(values.iter().copied()), values.len())
}

/// Median over one-minute windows of the RSA-derived breathing rate.
fn respiratory_rate(inside: &[&Sample], onset: DateTime<Utc>) -> Option<f64> {
    let mut rates: Vec<f64> = bins(inside, onset, ONE_MINUTE_S)
        .into_iter()
        .filter_map(|bin| {
            let rr: Vec<u32> = bin.iter().flat_map(|s| s.rr_ms.iter().copied()).collect();
            crate::respiration::rate_from_rr(&hrv::clean_rr(&rr))
        })
        .collect();
    if rates.is_empty() {
        return None;
    }
    rates.sort_by(|a, b| a.total_cmp(b));
    Some(rates[rates.len() / 2])
}

/// SpO₂: the strap measures in 30 s windows every 20 min. Group consecutive readings
/// into windows, take each window's median, then the median across windows.
fn spo2(inside: &[&Sample]) -> (Option<f64>, usize) {
    let mut windows: Vec<Vec<f64>> = Vec::new();
    let mut last_ts: Option<DateTime<Utc>> = None;
    for s in inside {
        let Some(v) = s.spo2_pct else { continue };
        match last_ts {
            Some(prev) if (s.ts - prev).num_seconds() <= SPO2_WINDOW_GAP_S => {
                windows
                    .last_mut()
                    .expect("window exists")
                    .push(f64::from(v));
            }
            _ => windows.push(vec![f64::from(v)]),
        }
        last_ts = Some(s.ts);
    }
    let mut medians: Vec<f64> = windows.iter().map(|w| median(w.clone())).collect();
    let count = medians.len();
    if medians.is_empty() {
        return (None, 0);
    }
    medians.sort_by(|a, b| a.total_cmp(b));
    (Some(medians[count / 2]), count)
}

fn bins<'a>(inside: &[&'a Sample], onset: DateTime<Utc>, width_s: i64) -> Vec<Vec<&'a Sample>> {
    let mut bins: Vec<Vec<&Sample>> = Vec::new();
    for s in inside {
        let index = ((s.ts - onset).num_seconds() / width_s) as usize;
        if bins.len() <= index {
            bins.resize_with(index + 1, Vec::new);
        }
        bins[index].push(s);
    }
    bins
}

fn mean(values: impl Iterator<Item = f64>) -> Option<f64> {
    let (sum, n) = values.fold((0.0, 0usize), |(s, n), v| (s + v, n + 1));
    (n > 0).then(|| sum / n as f64)
}

fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(|a, b| a.total_cmp(b));
    values[values.len() / 2]
}

#[cfg(test)]
mod tests;
