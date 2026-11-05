//! Descriptive progress, not a health score or biological-age model. Arithmetic
//! means and circular wake-time dispersion describe the recorded history only.
//! The 28-day windows and coverage gates are product safeguards, not clinical cutoffs.
use crate::CoreResult;
use chrono::{Duration, NaiveDate};
use serde::Serialize;
use snoop_analytics::{ALGO_VERSION, WORKOUT_ALGO_VERSION};
use snoop_storage::{InsightNight, PostgresStore, ProgressDay};
const PERIOD_DAYS: i64 = 28;
const MIN_DAYS: usize = 21;
const MIN_WEEK_DAYS: usize = 4;
const MIN_COMPLETE_WEEKS: usize = 3;
const MIN_DAY_COVERAGE: f64 = 0.75;
const MAX_SLEEP_GAP_S: f64 = 120.0;
const MINUTES_PER_DAY: f64 = 1440.0;

/// A dated comparison window; end is inclusive.
#[derive(Debug, Serialize)]
pub struct Period {
    /// First local date.
    pub start: NaiveDate,
    /// Last local date.
    pub end: NaiveDate,
}
/// A metric keeps observed means separate from eligibility for a comparison.
#[derive(Debug, Serialize)]
pub struct ProgressMetric {
    /// Stable display key.
    pub key: &'static str,
    /// Mean for available qualifying days or complete weeks.
    pub current: Option<f64>,
    /// Equivalent preceding window.
    pub previous: Option<f64>,
    /// Current minus previous, only when both have enough coverage.
    pub change: Option<f64>,
    /// Number of qualifying observations in the current window.
    pub current_count: usize,
    /// Number in the preceding window.
    pub previous_count: usize,
    /// Required observations before comparison.
    pub required_count: usize,
    /// Eight weekly averages; absent weeks are gaps, never zeroes.
    pub weeks: Vec<Option<f64>>,
}
/// Immutable response calculated from effective, corrected history.
#[derive(Debug, Serialize)]
pub struct Progress {
    /// IANA calendar zone.
    pub timezone: String,
    /// Last 28 complete local days.
    pub current: Period,
    /// Preceding 28 days.
    pub previous: Period,
    /// Sleep, wake variation, steps, walking, strength.
    pub metrics: Vec<ProgressMetric>,
}
/// Loads bounded history. No new derivations, migrations, or raw-data mutations.
/// # Errors
/// Database access or timezone conversion failure.
pub async fn progress(
    store: &PostgresStore,
    device: &str,
    today: NaiveDate,
    tz: &str,
) -> CoreResult<Option<Progress>> {
    let from = today - Duration::days(PERIOD_DAYS * 2);
    let Some(nights) = store
        .insight_snapshot(device, from, today - Duration::days(1), tz, ALGO_VERSION)
        .await?
    else {
        return Ok(None);
    };
    let days = store
        .progress_days(device, from, today, tz, WORKOUT_ALGO_VERSION)
        .await?;
    Ok(Some(calculate(today, tz, &nights.nights, &days)))
}
fn mean(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().sum::<f64>() / values.len() as f64)
}
fn wake_variation(values: &[f64]) -> Option<f64> {
    if values.len() < 2 {
        return None;
    }
    let angles: Vec<_> = values
        .iter()
        .map(|v| v / MINUTES_PER_DAY * std::f64::consts::TAU)
        .collect();
    let x = angles.iter().map(|a| a.cos()).sum::<f64>() / angles.len() as f64;
    let y = angles.iter().map(|a| a.sin()).sum::<f64>() / angles.len() as f64;
    let length = x.hypot(y).clamp(f64::EPSILON, 1.0);
    Some((-2.0 * length.ln()).sqrt() * MINUTES_PER_DAY / std::f64::consts::TAU)
}
fn metric(
    key: &'static str,
    values: &[Option<f64>],
    weekly_total: bool,
    circular: bool,
) -> ProgressMetric {
    let aggregate = |xs: &[f64]| {
        if circular {
            wake_variation(xs)
        } else {
            mean(xs)
        }
    };
    let weeks: Vec<_> = values
        .chunks(7)
        .map(|xs| {
            let observed: Vec<_> = xs.iter().flatten().copied().collect();
            if weekly_total {
                (observed.len() == 7).then(|| observed.iter().sum())
            } else if observed.len() >= MIN_WEEK_DAYS {
                aggregate(&observed)
            } else {
                None
            }
        })
        .collect();
    let (previous_values, current_values): (Vec<_>, Vec<_>) = if weekly_total {
        (
            weeks[..4].iter().flatten().copied().collect(),
            weeks[4..].iter().flatten().copied().collect(),
        )
    } else {
        (
            values[..28].iter().flatten().copied().collect(),
            values[28..].iter().flatten().copied().collect(),
        )
    };
    let previous = aggregate(&previous_values);
    let current = aggregate(&current_values);
    let required_count = if weekly_total {
        MIN_COMPLETE_WEEKS
    } else {
        MIN_DAYS
    };
    ProgressMetric {
        key,
        current,
        previous,
        change: current
            .zip(previous)
            .filter(|_| {
                current_values.len() >= required_count && previous_values.len() >= required_count
            })
            .map(|(c, p)| c - p),
        current_count: current_values.len(),
        previous_count: previous_values.len(),
        required_count,
        weeks,
    }
}
fn calculate(
    today: NaiveDate,
    tz: &str,
    nights: &[InsightNight],
    days: &[ProgressDay],
) -> Progress {
    let from = today - Duration::days(56);
    let mut sleep = vec![None; 56];
    let mut wake = sleep.clone();
    let mut steps = sleep.clone();
    let mut walking = sleep.clone();
    let mut strength = sleep.clone();
    for night in nights {
        let index = (night.day - from).num_days();
        if !(0..56).contains(&index) || night.pending || !night.complete {
            continue;
        }
        let value = |key: &str| {
            night
                .metrics
                .pointer(key)
                .and_then(serde_json::Value::as_f64)
                .filter(|v| v.is_finite())
        };
        let coverage = value("/sleep/window/coverage_s").unwrap_or(0.0);
        if night.duration_s <= 0 || night.duration_s as f64 - coverage > MAX_SLEEP_GAP_S {
            continue;
        }
        sleep[index as usize] =
            value("/sleep/window/asleep_s").filter(|s| *s > 0.0 && *s <= night.duration_s as f64);
        if sleep[index as usize].is_some() && night.timezone == tz {
            wake[index as usize] = Some(night.wake_minute);
        }
    }
    for day in days {
        let index = (day.day - from).num_days();
        if !(0..56).contains(&index)
            || day.day_seconds <= 0.0
            || day.samples as f64 / day.day_seconds < MIN_DAY_COVERAGE
        {
            continue;
        }
        steps[index as usize] = day.steps.filter(|v| *v >= 0).map(|v| v as f64);
        walking[index as usize] = day.walking_s.filter(|v| *v >= 0).map(|v| v as f64 / 60.0);
        if !day.pending {
            strength[index as usize] = Some(if day.strength { 1.0 } else { 0.0 });
        }
    }
    Progress {
        timezone: tz.into(),
        current: Period {
            start: today - Duration::days(28),
            end: today - Duration::days(1),
        },
        previous: Period {
            start: from,
            end: today - Duration::days(29),
        },
        metrics: vec![
            metric("sleep", &sleep, false, false),
            metric("wake_variation", &wake, false, true),
            metric("steps", &steps, false, false),
            metric("walking", &walking, true, false),
            metric("strength", &strength, true, false),
        ],
    }
}
#[cfg(test)]
#[path = "progress/tests.rs"]
mod tests;
