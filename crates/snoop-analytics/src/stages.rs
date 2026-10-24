//! Four-class sleep staging (wake / light / deep / REM) from one-second samples.
//!
//! Without EEG, stages are inferred from autonomic and motion signals. The approach
//! follows the published wrist-device literature:
//!
//! - Epochs of 30 s, the polysomnography convention.
//! - Motion per epoch from the strap's dynamic acceleration and from the change in
//!   the wrist's posture angle (van Hees et al. 2015).
//! - Cardiac features per epoch over a centred five-minute window: mean heart rate,
//!   heart-rate variability on two time scales as a difference of Gaussians (Walch
//!   et al. 2019), RMSSD (Task Force 1996), and breathing rate and its variability
//!   from respiratory sinus arrhythmia.
//! - Rules against night-relative percentiles: wake shows motion with cardiac
//!   activation; deep sleep shows stillness, low heart rate, high RMSSD and regular
//!   breathing; REM shows stillness with cardiac activation and irregular breathing;
//!   everything else is light sleep.
//! - Physiological smoothing: five-epoch majority filter, no REM in the first fifteen
//!   minutes, deep sleep demoted after the first two thirds of the night, fragments
//!   under three minutes absorbed into their neighbours.
//!
//! Published four-class agreement with polysomnography for this class of method is
//! roughly 65–73 %, and light versus deep is the weakest distinction. Deep-sleep
//! minutes are therefore the least reliable number here.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::hrv;
use crate::respiration;
use crate::sleep::{Sample, SleepWindow};

pub const EPOCH_S: i64 = 30;
const FEATURE_WINDOW_S: i64 = 300;
const MOTION_THRESHOLD_G: f32 = 0.02;
const DOG_SIGMA_SHORT_S: f64 = 120.0;
const DOG_SIGMA_LONG_S: f64 = 600.0;
const SMOOTH_EPOCHS: usize = 5;
const NO_REM_AFTER_ONSET_S: i64 = 15 * 60;
const DEEP_ALLOWED_FRACTION: f64 = 2.0 / 3.0;
const FRAGMENT_MIN_EPOCHS: usize = 6;
const MIN_BEATS_FOR_RMSSD: usize = 60;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Stage {
    Wake,
    Light,
    Deep,
    Rem,
}

/// A run of consecutive epochs in one stage.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StageSegment {
    pub stage: Stage,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

/// AASM-style roll-up of a hypnogram.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StageSummary {
    pub wake_s: i64,
    pub light_s: i64,
    pub deep_s: i64,
    pub rem_s: i64,
    /// Time from window onset to the first non-wake epoch.
    pub sleep_latency_s: i64,
    /// Time from sleep onset to the first REM epoch, when REM occurred.
    pub rem_latency_s: Option<i64>,
    pub epochs: usize,
    /// Epochs with enough cardiac data to classify (others fall back to light).
    pub epochs_with_cardiac: usize,
}

/// Per-epoch features, kept for inspection and tests.
#[derive(Debug, Clone, PartialEq)]
pub struct EpochFeatures {
    pub start: DateTime<Utc>,
    pub strap_awake: bool,
    pub move_frac: f64,
    pub angle_change_deg: Option<f64>,
    pub hr_mean: Option<f64>,
    pub hr_dog: Option<f64>,
    pub rmssd: Option<f64>,
    pub resp_rate: Option<f64>,
    pub resp_var: Option<f64>,
}

/// Stages a sleep window. Returns the segments and their summary.
pub fn stage_window(samples: &[Sample], window: &SleepWindow) -> (Vec<StageSegment>, StageSummary) {
    let inside: Vec<&Sample> = samples
        .iter()
        .filter(|s| s.ts >= window.onset && s.ts <= window.offset)
        .collect();
    let features = epoch_features(&inside, window.onset, window.offset);
    if features.is_empty() {
        return (
            Vec::new(),
            StageSummary {
                wake_s: 0,
                light_s: 0,
                deep_s: 0,
                rem_s: 0,
                sleep_latency_s: 0,
                rem_latency_s: None,
                epochs: 0,
                epochs_with_cardiac: 0,
            },
        );
    }
    let raw: Vec<Stage> = classify(&features);
    let smoothed = smooth(&raw, &features, window);
    let segments = segments(&smoothed, &features, window.offset);
    let summary = summarise(&smoothed, &features, window.onset);
    (segments, summary)
}

fn epoch_features(
    inside: &[&Sample],
    onset: DateTime<Utc>,
    offset: DateTime<Utc>,
) -> Vec<EpochFeatures> {
    let total_s = (offset - onset).num_seconds() + 1;
    let n_epochs = ((total_s + EPOCH_S - 1) / EPOCH_S) as usize;
    if n_epochs == 0 || inside.is_empty() {
        return Vec::new();
    }

    // One-second HR series (NaN where missing), then interpolated for the DoG filter.
    let mut hr_series = vec![f64::NAN; total_s as usize];
    for s in inside {
        if let Some(hr) = s.hr {
            let i = (s.ts - onset).num_seconds() as usize;
            if i < hr_series.len() {
                hr_series[i] = f64::from(hr);
            }
        }
    }
    let hr_filled = interpolate(&hr_series);
    let dog = difference_of_gaussians(&hr_filled, DOG_SIGMA_SHORT_S, DOG_SIGMA_LONG_S);

    (0..n_epochs)
        .map(|e| {
            let start = onset + Duration::seconds(e as i64 * EPOCH_S);
            let end = start + Duration::seconds(EPOCH_S);
            let epoch: Vec<&&Sample> = inside
                .iter()
                .filter(|s| s.ts >= start && s.ts < end)
                .collect();
            let centre = start + Duration::seconds(EPOCH_S / 2);
            let win_lo = centre - Duration::seconds(FEATURE_WINDOW_S / 2);
            let win_hi = centre + Duration::seconds(FEATURE_WINDOW_S / 2);
            let window: Vec<&&Sample> = inside
                .iter()
                .filter(|s| s.ts >= win_lo && s.ts < win_hi)
                .collect();

            let strap_awake = !epoch.is_empty()
                && epoch
                    .iter()
                    .filter(|s| s.band_state != Sample::BAND_SLEEP)
                    .count()
                    * 2
                    > epoch.len();
            let moving = epoch
                .iter()
                .filter(|s| s.motion_g.is_some_and(|g| g > MOTION_THRESHOLD_G))
                .count();
            let move_frac = if epoch.is_empty() {
                0.0
            } else {
                moving as f64 / epoch.len() as f64
            };

            let angles: Vec<f64> = epoch
                .iter()
                .filter_map(|s| s.gravity_g)
                .map(posture_angle_deg)
                .collect();
            let angle_change_deg = (angles.len() >= 2).then(|| {
                angles.windows(2).map(|w| (w[1] - w[0]).abs()).sum::<f64>()
                    / (angles.len() - 1) as f64
            });

            let hrs: Vec<f64> = window.iter().filter_map(|s| s.hr).map(f64::from).collect();
            let hr_mean = (!hrs.is_empty()).then(|| hrs.iter().sum::<f64>() / hrs.len() as f64);

            let i0 = (start - onset).num_seconds().max(0) as usize;
            let i1 = (i0 + EPOCH_S as usize).min(dog.len());
            let hr_dog = (i1 > i0 && hr_mean.is_some())
                .then(|| dog[i0..i1].iter().map(|v| v.abs()).sum::<f64>() / (i1 - i0) as f64);

            let rr: Vec<u32> = window
                .iter()
                .flat_map(|s| s.rr_ms.iter().copied())
                .collect();
            let clean = hrv::clean_rr(&rr);
            let rmssd = (clean.len() >= MIN_BEATS_FOR_RMSSD)
                .then(|| hrv::rmssd(&clean))
                .flatten();

            let (resp_rate, resp_var) = breathing(&window, win_lo);

            EpochFeatures {
                start,
                strap_awake,
                move_frac,
                angle_change_deg,
                hr_mean,
                hr_dog,
                rmssd,
                resp_rate,
                resp_var,
            }
        })
        .collect()
}

/// Breathing rate over the five-minute window as the median of one-minute estimates,
/// and its variability as their standard deviation.
fn breathing(window: &[&&Sample], win_lo: DateTime<Utc>) -> (Option<f64>, Option<f64>) {
    let mut rates = Vec::new();
    for minute in 0..(FEATURE_WINDOW_S / 60) {
        let lo = win_lo + Duration::seconds(minute * 60);
        let hi = lo + Duration::seconds(60);
        let rr: Vec<u32> = window
            .iter()
            .filter(|s| s.ts >= lo && s.ts < hi)
            .flat_map(|s| s.rr_ms.iter().copied())
            .collect();
        if let Some(rate) = respiration::rate_from_rr(&hrv::clean_rr(&rr)) {
            rates.push(rate);
        }
    }
    if rates.len() < 2 {
        return (rates.first().copied(), None);
    }
    let mut sorted = rates.clone();
    sorted.sort_by(|a, b| a.total_cmp(b));
    let median = sorted[sorted.len() / 2];
    let mean = rates.iter().sum::<f64>() / rates.len() as f64;
    let var = rates.iter().map(|r| (r - mean).powi(2)).sum::<f64>() / (rates.len() - 1) as f64;
    (Some(median), Some(var.sqrt()))
}

/// Angle between the wrist's z axis and the horizontal plane (van Hees et al.).
fn posture_angle_deg(g: [f32; 3]) -> f64 {
    let (x, y, z) = (f64::from(g[0]), f64::from(g[1]), f64::from(g[2]));
    z.atan2((x * x + y * y).sqrt()).to_degrees()
}

fn interpolate(series: &[f64]) -> Vec<f64> {
    let mut out = series.to_vec();
    let mut last: Option<(usize, f64)> = None;
    let mut i = 0;
    while i < out.len() {
        if out[i].is_nan() {
            let next = (i + 1..out.len()).find(|&j| !out[j].is_nan());
            match (last, next) {
                (Some((li, lv)), Some(ni)) => {
                    let nv = out[ni];
                    for (k, v) in out.iter_mut().enumerate().take(ni).skip(i) {
                        *v = lv + (nv - lv) * (k - li) as f64 / (ni - li) as f64;
                    }
                    i = ni;
                    continue;
                }
                (Some((_, lv)), None) => {
                    for v in out[i..].iter_mut() {
                        *v = lv;
                    }
                    break;
                }
                (None, Some(ni)) => {
                    let nv = out[ni];
                    for v in out[i..ni].iter_mut() {
                        *v = nv;
                    }
                    i = ni;
                    continue;
                }
                (None, None) => {
                    for v in out.iter_mut() {
                        *v = 0.0;
                    }
                    break;
                }
            }
        }
        last = Some((i, out[i]));
        i += 1;
    }
    out
}

/// Gaussian smoothing with reflected edges, at two scales, subtracted.
fn difference_of_gaussians(series: &[f64], sigma_short: f64, sigma_long: f64) -> Vec<f64> {
    let short = gaussian(series, sigma_short);
    let long = gaussian(series, sigma_long);
    short.iter().zip(&long).map(|(a, b)| a - b).collect()
}

fn gaussian(series: &[f64], sigma: f64) -> Vec<f64> {
    let radius = (3.0 * sigma) as isize;
    let kernel: Vec<f64> = (-radius..=radius)
        .map(|k| (-(k as f64).powi(2) / (2.0 * sigma * sigma)).exp())
        .collect();
    let norm: f64 = kernel.iter().sum();
    let n = series.len() as isize;
    (0..n)
        .map(|i| {
            let mut acc = 0.0;
            for (j, w) in kernel.iter().enumerate() {
                let mut idx = i + j as isize - radius;
                if idx < 0 {
                    idx = -idx;
                }
                if idx >= n {
                    idx = 2 * (n - 1) - idx;
                }
                acc += w * series[idx.clamp(0, n - 1) as usize];
            }
            acc / norm
        })
        .collect()
}

fn percentile(values: &mut [f64], p: f64) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(|a, b| a.total_cmp(b));
    let idx = ((values.len() - 1) as f64 * p).round() as usize;
    Some(values[idx])
}

const WAKE_MOVE_FRAC: f64 = 0.15;
const STILL_MOVE_FRAC: f64 = 0.10;
const HR_LOW_PCT: f64 = 0.25;
const HR_HIGH_PCT: f64 = 0.70;
const DOG_HIGH_PCT: f64 = 0.70;
const RMSSD_HIGH_PCT: f64 = 0.70;
const RESP_VAR_HIGH_PCT: f64 = 0.65;
const RESP_VAR_LOW_PCT: f64 = 0.50;

fn classify(features: &[EpochFeatures]) -> Vec<Stage> {
    // Reference distributions over epochs the strap considers asleep.
    let asleep: Vec<&EpochFeatures> = features.iter().filter(|f| !f.strap_awake).collect();
    let refs = if asleep.is_empty() {
        features.iter().collect()
    } else {
        asleep
    };
    let mut hr: Vec<f64> = refs.iter().filter_map(|f| f.hr_mean).collect();
    let mut dog: Vec<f64> = refs.iter().filter_map(|f| f.hr_dog).collect();
    let mut rmssd: Vec<f64> = refs.iter().filter_map(|f| f.rmssd).collect();
    let mut rv: Vec<f64> = refs.iter().filter_map(|f| f.resp_var).collect();
    let hr_low = percentile(&mut hr, HR_LOW_PCT);
    let hr_high = percentile(&mut hr, HR_HIGH_PCT);
    let dog_high = percentile(&mut dog, DOG_HIGH_PCT);
    let rmssd_high = percentile(&mut rmssd, RMSSD_HIGH_PCT);
    let rv_high = percentile(&mut rv, RESP_VAR_HIGH_PCT);
    let rv_low = percentile(&mut rv, RESP_VAR_LOW_PCT);

    features
        .iter()
        .map(|f| {
            let activated = f.hr_mean.zip(hr_high).is_some_and(|(v, t)| v > t)
                || f.hr_dog.zip(dog_high).is_some_and(|(v, t)| v > t);
            if f.strap_awake
                || (f.move_frac >= WAKE_MOVE_FRAC && (activated || f.hr_mean.is_none()))
            {
                return Stage::Wake;
            }
            let still = f.move_frac <= STILL_MOVE_FRAC;
            let low_hr = f.hr_mean.zip(hr_low).is_some_and(|(v, t)| v < t);
            let high_rmssd = f.rmssd.zip(rmssd_high).is_some_and(|(v, t)| v > t);
            let regular = match (f.resp_var, rv_low) {
                (Some(v), Some(t)) => v <= t,
                _ => true,
            };
            let irregular = f.resp_var.zip(rv_high).is_some_and(|(v, t)| v > t);
            let both_cardiac = f.hr_mean.zip(hr_high).is_some_and(|(v, t)| v > t)
                && f.hr_dog.zip(dog_high).is_some_and(|(v, t)| v > t);

            if still && high_rmssd && low_hr && regular {
                Stage::Deep
            } else if still && activated && (irregular || (f.resp_var.is_none() && both_cardiac)) {
                Stage::Rem
            } else {
                Stage::Light
            }
        })
        .collect()
}

fn smooth(raw: &[Stage], features: &[EpochFeatures], window: &SleepWindow) -> Vec<Stage> {
    let n = raw.len();
    let half = SMOOTH_EPOCHS / 2;
    let mut out: Vec<Stage> = (0..n)
        .map(|i| {
            let lo = i.saturating_sub(half);
            let hi = (i + half + 1).min(n);
            let mut counts = [0usize; 4];
            for s in &raw[lo..hi] {
                counts[*s as usize] += 1;
            }
            let best = counts
                .iter()
                .enumerate()
                .max_by_key(|(_, c)| **c)
                .map(|(i, _)| i)
                .unwrap_or(1);
            match best {
                0 => Stage::Wake,
                2 => Stage::Deep,
                3 => Stage::Rem,
                _ => Stage::Light,
            }
        })
        .collect();

    let total_s = (window.offset - window.onset).num_seconds().max(1);
    for (i, stage) in out.iter_mut().enumerate() {
        let elapsed = (features[i].start - window.onset).num_seconds();
        if *stage == Stage::Rem && elapsed < NO_REM_AFTER_ONSET_S {
            *stage = Stage::Light;
        }
        if *stage == Stage::Deep && elapsed as f64 > total_s as f64 * DEEP_ALLOWED_FRACTION {
            *stage = Stage::Light;
        }
    }

    // Absorb short fragments into the preceding stage.
    let mut i = 0;
    while i < n {
        let mut j = i;
        while j < n && out[j] == out[i] {
            j += 1;
        }
        if j - i < FRAGMENT_MIN_EPOCHS && i > 0 && j < n {
            let fill = out[i - 1];
            for s in out[i..j].iter_mut() {
                *s = fill;
            }
        }
        i = j;
    }
    out
}

fn segments(
    stages: &[Stage],
    features: &[EpochFeatures],
    offset: DateTime<Utc>,
) -> Vec<StageSegment> {
    let mut out: Vec<StageSegment> = Vec::new();
    for (i, stage) in stages.iter().enumerate() {
        let start = features[i].start;
        let end = (start + Duration::seconds(EPOCH_S)).min(offset + Duration::seconds(1));
        match out.last_mut() {
            Some(last) if last.stage == *stage => last.end = end,
            _ => out.push(StageSegment {
                stage: *stage,
                start,
                end,
            }),
        }
    }
    out
}

fn summarise(stages: &[Stage], features: &[EpochFeatures], onset: DateTime<Utc>) -> StageSummary {
    let mut totals = [0i64; 4];
    for s in stages {
        totals[*s as usize] += EPOCH_S;
    }
    let first_sleep = stages.iter().position(|s| *s != Stage::Wake);
    let sleep_latency_s = first_sleep.map_or(0, |i| (features[i].start - onset).num_seconds());
    let rem_latency_s = first_sleep.and_then(|fs| {
        stages[fs..]
            .iter()
            .position(|s| *s == Stage::Rem)
            .map(|k| (features[fs + k].start - features[fs].start).num_seconds())
    });
    StageSummary {
        wake_s: totals[0],
        light_s: totals[1],
        deep_s: totals[2],
        rem_s: totals[3],
        sleep_latency_s,
        rem_latency_s,
        epochs: stages.len(),
        epochs_with_cardiac: features.iter().filter(|f| f.rmssd.is_some()).count(),
    }
}

#[cfg(test)]
mod tests;
