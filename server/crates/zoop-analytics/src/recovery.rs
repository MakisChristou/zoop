//! Zoop Recovery v1: a conservative index, ported from frozen research candidate v0.3.
//!
//! Plews et al. (2014), doi:10.1123/ijspp.2013-0455 supports repeated personal
//! lnRMSSD comparisons; Banks et al. (2010), PMID:20815182 motivates retaining
//! recent sleep restriction. Neither validates this formula, its weights, bands,
//! eight-hour reference, or interpretation as exercise readiness. These are
//! explicit Zoop conventions, not WHOOP parity or a physiological percentage.
use crate::insights::{Night, Reading};
use chrono::NaiveDate;
use serde::Serialize;
use std::collections::BTreeSet;

/// Independently versioned; changing this never re-derives sleep or workouts.
pub const RECOVERY_VERSION: i32 = 1;
/// Fixed methodological reference, independent of a user's presentation goal.
pub const REFERENCE_SECONDS: u32 = 28_800;

/// Supporting components on the same conventional 0–100 scale.
#[derive(Debug, Clone, Serialize)]
pub struct Components {
    pub hrv: f64,
    pub resting_hr: f64,
    pub last_sleep: f64,
    pub recent_sleep: f64,
}
/// Server-owned score. Missing data is never represented by zero.
#[derive(Debug, Clone, Serialize)]
pub struct Recovery {
    pub version: i32,
    pub method: &'static str,
    pub state: &'static str,
    pub score: Option<u8>,
    pub baseline_count: usize,
    pub recent_count: usize,
    pub reference_seconds: u32,
    pub components: Option<Components>,
    pub limiting: Vec<&'static str>,
    pub conflict: bool,
    pub band: Option<&'static str>,
}
impl Recovery {
    fn unavailable(state: &'static str, baseline_count: usize, recent_count: usize) -> Self {
        Self {
            version: RECOVERY_VERSION,
            method: "zoop-recovery-v1",
            state,
            score: None,
            baseline_count,
            recent_count,
            reference_seconds: REFERENCE_SECONDS,
            components: None,
            limiting: vec![],
            conflict: false,
            band: None,
        }
    }
}
fn value(r: &Reading) -> Option<f64> {
    r.value
        .filter(|v| r.quality == "good" && v.is_finite() && *v > 0.0)
}
fn valid(n: &Night) -> bool {
    n.state == "ready"
        && value(&n.sleep).is_some_and(|v| v <= 86400.0)
        && value(&n.hrv).is_some()
        && value(&n.resting_hr).is_some()
}
fn mean(values: &[f64]) -> f64 {
    values.iter().sum::<f64>() / values.len() as f64
}
fn sd(values: &[f64], centre: f64) -> f64 {
    (values.iter().map(|v| (v - centre).powi(2)).sum::<f64>() / (values.len() - 1) as f64).sqrt()
}
fn sleep_fraction(n: &Night) -> f64 {
    (n.sleep.value.unwrap_or(0.0) / f64::from(REFERENCE_SECONDS)).min(1.0)
}
// Floating-point log/SD implementations can disagree by a few ULPs at an exact
// half. Treat a 1e-9-point neighborhood below the boundary as that boundary.
fn rounded_score(value: f64) -> u8 {
    (value + 0.5 + 1e-9).floor() as u8
}
/// Calculates from already device-scoped, quality-gated main sleeps. Calendar
/// dates, saved timezones and duplicate detection precede eligibility filtering.
pub fn calculate(day: NaiveDate, timezone: &str, nights: &[Night], pending: bool) -> Recovery {
    if pending {
        return Recovery::unavailable("updating", 0, 0);
    }
    let current: Vec<_> = nights.iter().filter(|n| n.day == day).collect();
    if current.len() > 1 {
        return Recovery::unavailable("ambiguous_history", 0, 0);
    }
    let Some(target) = current.first() else {
        return Recovery::unavailable("no_sleep", 0, 0);
    };
    if target.state == "updating" {
        return Recovery::unavailable("updating", 0, 0);
    }
    if target.state == "awaiting_sync" {
        return Recovery::unavailable("awaiting_sync", 0, 0);
    }
    if target.timezone != timezone || !valid(target) {
        return Recovery::unavailable("insufficient_data", 0, 0);
    }
    let scoped: Vec<_> = nights
        .iter()
        .filter(|n| {
            let age = (day - n.day).num_days();
            (1..=28).contains(&age) && n.timezone == target.timezone
        })
        .collect();
    if scoped.iter().map(|n| n.day).collect::<BTreeSet<_>>().len() != scoped.len() {
        return Recovery::unavailable("ambiguous_history", 0, 0);
    }
    let mut prior: Vec<_> = scoped.into_iter().filter(|n| valid(n)).collect();
    prior.sort_by_key(|n| n.day);
    let count = prior.len();
    if count < 14 {
        return Recovery::unavailable("learning", count, 0);
    }
    let recent: Vec<_> = prior
        .iter()
        .copied()
        .filter(|n| (day - n.day).num_days() < 7)
        .chain(std::iter::once(*target))
        .collect();
    if recent.len() < 5 {
        return Recovery::unavailable("insufficient_recent_data", count, recent.len());
    }
    let hvals: Vec<_> = prior
        .iter()
        .map(|n| n.hrv.value.unwrap_or(1.0).ln())
        .collect();
    let rvals: Vec<_> = prior
        .iter()
        .map(|n| n.resting_hr.value.unwrap_or(0.0))
        .collect();
    let hmean = mean(&hvals);
    let rmean = mean(&rvals);
    let h = (target.hrv.value.unwrap_or(1.0).ln() - hmean) / sd(&hvals, hmean).max(1.05_f64.ln());
    let r = (target.resting_hr.value.unwrap_or(0.0) - rmean) / sd(&rvals, rmean).max(1.0);
    if h > 2.0 || r < -2.0 {
        return Recovery::unavailable("unusual_signals", count, recent.len());
    }
    let components = Components {
        hrv: (75.0 + 15.0 * h).clamp(0.0, 100.0),
        resting_hr: (75.0 - 15.0 * r).clamp(0.0, 100.0),
        last_sleep: 100.0 * sleep_fraction(target).powi(2),
        recent_sleep: 100.0
            * mean(&recent.iter().map(|n| sleep_fraction(n)).collect::<Vec<_>>()).powi(2),
    };
    let parts = [
        ("hrv", components.hrv),
        ("resting_hr", components.resting_hr),
        ("last_sleep", components.last_sleep),
        ("recent_sleep", components.recent_sleep),
    ];
    let least = parts.iter().map(|(_, v)| *v).fold(100.0, f64::min);
    let score = rounded_score(least);
    Recovery {
        version: RECOVERY_VERSION,
        method: "zoop-recovery-v1",
        state: "ready",
        score: Some(score),
        baseline_count: count,
        recent_count: recent.len(),
        reference_seconds: REFERENCE_SECONDS,
        components: Some(components),
        limiting: parts
            .into_iter()
            .filter(|(_, v)| (v - least).abs() <= 1e-9)
            .map(|(key, _)| key)
            .collect(),
        conflict: (h > 1.0 && r > 1.0) || (h < -1.0 && r < -1.0),
        band: Some(if score < 34 {
            "low"
        } else if score < 67 {
            "moderate"
        } else {
            "high"
        }),
    }
}
#[cfg(test)]
mod tests;
