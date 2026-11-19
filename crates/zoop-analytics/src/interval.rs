//! Summaries of user-selected intervals, using the existing Edwards zones/TRIMP
//! (`zones`), Keytel calorie estimates (`energy`), and counter increments (`bouts`).
//! Selection changes the observation window, not the scientific methods. No missing
//! seconds are filled, and automatic detector duration thresholds do not apply.

use crate::{
    bouts::{ActivitySample, step_increments, steps_between},
    energy::kcal_over_seconds,
    workouts::Physiology,
    zones::{ZoneSeconds, load},
};
use chrono::{DateTime, Utc};
use serde::Serialize;

/// Measured values within a half-open interval, with independent HR coverage.
#[derive(Debug, Clone, Serialize)]
pub struct IntervalSummary {
    pub coverage_s: i64,
    pub hr_coverage_s: i64,
    pub avg_hr: Option<f64>,
    pub max_hr: Option<u8>,
    pub zones: Option<ZoneSeconds>,
    pub trimp: Option<f64>,
    pub load: Option<f64>,
    pub kcal: Option<f64>,
    pub steps: Option<i64>,
}

/// Summarises only actual readings. Samples are sorted, unique, one per second;
/// callers include a preceding sample when available for the first step increment.
pub fn summarize_interval(
    samples: &[ActivitySample],
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    physiology: &Physiology,
) -> IntervalSummary {
    let window = &samples
        [samples.partition_point(|s| s.ts < start)..samples.partition_point(|s| s.ts < end)];
    let hrs: Vec<_> = window
        .iter()
        .filter_map(|s| s.hr.filter(|h| *h > 0))
        .collect();
    let zones = (!hrs.is_empty()).then(|| {
        let mut zones = ZoneSeconds::default();
        for hr in &hrs {
            zones.add(f64::from(*hr), physiology.hr_max);
        }
        zones
    });
    let trimp = zones.as_ref().map(ZoneSeconds::trimp);
    IntervalSummary {
        coverage_s: window.len() as i64,
        hr_coverage_s: hrs.len() as i64,
        avg_hr: (!hrs.is_empty())
            .then(|| hrs.iter().map(|h| f64::from(*h)).sum::<f64>() / hrs.len() as f64),
        max_hr: hrs.iter().copied().max(),
        trimp,
        load: trimp.map(load),
        zones,
        kcal: physiology
            .body
            .as_ref()
            .filter(|_| !hrs.is_empty())
            .map(|b| kcal_over_seconds(b, hrs.iter().map(|h| f64::from(*h)))),
        steps: window
            .iter()
            .any(|s| s.steps.is_some())
            .then(|| steps_between(samples, &step_increments(samples), start, end)),
    }
}

/// Removes owned correction windows from a candidate before automatic detection is
/// rerun on each remaining fragment, preventing the rest-gap rule joining across edits.
pub fn unclaimed_intervals(
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    scopes: &[(DateTime<Utc>, DateTime<Utc>)],
) -> Vec<(DateTime<Utc>, DateTime<Utc>)> {
    let mut fragments = vec![(start, end)];
    for &(a, b) in scopes {
        fragments = fragments
            .into_iter()
            .flat_map(|(s, e)| {
                if b <= s || a >= e {
                    vec![(s, e)]
                } else {
                    let mut out = Vec::new();
                    if s < a {
                        out.push((s, a));
                    }
                    if b < e {
                        out.push((b, e));
                    }
                    out
                }
            })
            .collect();
    }
    fragments
}

#[cfg(test)]
mod tests;
