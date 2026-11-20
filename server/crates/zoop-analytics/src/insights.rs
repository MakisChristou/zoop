//! Descriptive personal comparisons, independently versioned from sleep detection.
//!
//! Plews et al. (2014), doi:10.1123/ijspp.2013-0455, supports repeated individual
//! lnRMSSD comparisons. Fischer et al. (2021), doi:10.1093/sleep/zsab103, describes
//! variability of sleep timing. These observations are not a recovery score.
//! The 28-day window, 7/14 learning gates and one-SD descriptive band are product
//! conventions, not clinical cutoffs or a validated overnight readiness model.
use chrono::{Duration, NaiveDate};
use serde::Serialize;
mod outlook;
#[cfg(test)]
mod tests;
pub use outlook::{Comparison, Outlook};
/// Change when comparison rules change; sleep and workout versions are independent.
pub const INSIGHTS_VERSION: i32 = 2;
/// Previous calendar days, excluding the assessed night.
pub const BASELINE_DAYS: i64 = 28;
const EARLY_COUNT: usize = 7;
const ESTABLISHED_COUNT: usize = 14;
const WEEK_COUNT: usize = 5;

/// One main sleep; quality gates are independently applied to each measurement.
#[derive(Debug, Clone)]
pub struct Night {
    pub day: NaiveDate,
    pub id: i64,
    pub revision: i64,
    pub state: &'static str,
    pub sleep: Reading,
    pub hrv: Reading,
    pub resting_hr: Reading,
    pub onset_minute: f64,
    pub wake_minute: f64,
    pub timezone: String,
}
/// Raw displayed value and its eligibility for comparison.
#[derive(Debug, Clone)]
pub struct Reading {
    pub value: Option<f64>,
    pub quality: &'static str,
}
/// A daily observation retained for a small chart; gaps remain gaps.
#[derive(Debug, Serialize)]
pub struct Point {
    pub day: NaiveDate,
    pub value: Option<f64>,
}
/// Personal reference calculated strictly before the selected date.
#[derive(Debug, Serialize)]
pub struct Baseline {
    pub state: &'static str,
    pub count: usize,
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub average: Option<f64>,
    pub lower: Option<f64>,
    pub upper: Option<f64>,
}
/// Seven-day measurement summary; comparison requires sufficient data in both weeks.
#[derive(Debug, Serialize)]
pub struct Week {
    pub count: usize,
    pub average: Option<f64>,
    pub previous_average: Option<f64>,
}
/// One metric with explicit missing-data and learning states.
#[derive(Debug, Serialize)]
pub struct Metric {
    pub key: &'static str,
    pub value: Option<f64>,
    pub quality: &'static str,
    pub baseline: Baseline,
    pub relation: Option<&'static str>,
    pub comparison: Option<Comparison>,
    pub history: Vec<Point>,
    pub week: Week,
}
/// Clock-time variation in minutes, not a sleep regularity index.
#[derive(Debug, Serialize)]
pub struct Timing {
    pub count: usize,
    pub asleep_sd_min: Option<f64>,
    pub wake_sd_min: Option<f64>,
}
/// A brief and its complete supporting data, calculated from one consistent snapshot.
#[derive(Debug, Serialize)]
pub struct MorningInsights {
    pub version: i32,
    pub day: NaiveDate,
    pub timezone: String,
    pub state: &'static str,
    pub sleep_id: Option<i64>,
    pub sleep_revision: Option<i64>,
    pub metrics: Vec<Metric>,
    pub observations: Vec<String>,
    pub timing: Timing,
    pub outlook: Outlook,
    pub recovery: crate::recovery::Recovery,
}
/// Creates a historical or current brief. Later dates are never included.
pub fn calculate(
    day: NaiveDate,
    timezone: &str,
    nights: &[Night],
    pending: bool,
) -> MorningInsights {
    let current = nights.iter().find(|n| n.day == day);
    let state = if pending {
        "updating"
    } else {
        current.map_or("no_sleep", |n| n.state)
    };
    let metrics = vec![
        metric("sleep", day, nights, current, state),
        metric("hrv", day, nights, current, state),
        metric("resting_hr", day, nights, current, state),
    ];
    let observations = observations(&metrics, state);
    MorningInsights {
        version: INSIGHTS_VERSION,
        day,
        timezone: timezone.into(),
        state,
        sleep_id: current.map(|n| n.id),
        sleep_revision: current.map(|n| n.revision),
        timing: timing(day, nights),
        outlook: outlook::summarize(&metrics, state),
        recovery: crate::recovery::calculate(day, timezone, nights, pending),
        metrics,
        observations,
    }
}
fn reading<'a>(n: &'a Night, key: &str) -> &'a Reading {
    match key {
        "sleep" => &n.sleep,
        "hrv" => &n.hrv,
        _ => &n.resting_hr,
    }
}
fn usable(n: &Night, key: &str) -> Option<f64> {
    let r = reading(n, key);
    (n.state == "ready" && r.quality == "good")
        .then_some(r.value)
        .flatten()
        .filter(|v| v.is_finite() && *v > 0.0)
}
fn transform(v: f64, key: &str) -> f64 {
    if key == "hrv" { v.ln() } else { v }
}
fn inverse(v: f64, key: &str) -> f64 {
    if key == "hrv" { v.exp() } else { v }
}
fn mean(v: &[f64]) -> Option<f64> {
    (!v.is_empty()).then(|| v.iter().sum::<f64>() / v.len() as f64)
}
fn deviation(v: &[f64], avg: f64) -> f64 {
    if v.len() < 2 {
        return 0.0;
    }
    (v.iter().map(|x| (x - avg).powi(2)).sum::<f64>() / (v.len() - 1) as f64).sqrt()
}
fn metric(
    key: &'static str,
    day: NaiveDate,
    nights: &[Night],
    current: Option<&Night>,
    state: &str,
) -> Metric {
    let from = day - Duration::days(BASELINE_DAYS);
    let prior: Vec<_> = nights
        .iter()
        .filter(|n| n.day >= from && n.day < day)
        .filter_map(|n| usable(n, key))
        .map(|v| transform(v, key))
        .collect();
    let count = prior.len();
    let avg = mean(&prior).filter(|_| count >= EARLY_COUNT);
    let sd = avg.map(|a| deviation(&prior, a));
    // Avoid declaring tiny differences meaningful when the observed spread is zero.
    let floor = match key {
        "sleep" => 900.0,
        "hrv" => 1.05_f64.ln(),
        _ => 1.0,
    };
    let width = sd.map(|s| s.max(floor));
    let lower = avg.zip(width).map(|(a, s)| inverse(a - s, key).max(0.0));
    let upper = avg.zip(width).map(|(a, s)| inverse(a + s, key));
    let r = current.map(|n| reading(n, key));
    let value = r
        .and_then(|r| r.value)
        .filter(|v| v.is_finite() && *v > 0.0);
    let quality = if state != "ready" {
        state
    } else {
        r.map_or("missing", |r| r.quality)
    };
    let quality = match quality {
        "ready" | "good" => "good",
        "updating" => "updating",
        "awaiting_sync" => "awaiting_sync",
        "no_sleep" => "no_sleep",
        "limited" => "limited",
        _ => "missing",
    };
    let relation = if quality == "good" && count >= ESTABLISHED_COUNT {
        value.zip(lower.zip(upper)).map(|(v, (l, u))| {
            if v < l {
                "lower"
            } else if v > u {
                "higher"
            } else {
                "similar"
            }
        })
    } else {
        None
    };
    let week_values = |start, end| -> Vec<f64> {
        nights
            .iter()
            .filter(|n| n.day >= start && n.day <= end)
            .filter_map(|n| usable(n, key))
            .map(|v| transform(v, key))
            .collect()
    };
    let week = week_values(day - Duration::days(6), day);
    let previous = week_values(day - Duration::days(13), day - Duration::days(7));
    let history = (0..=BASELINE_DAYS)
        .map(|offset| {
            let date = from + Duration::days(offset);
            Point {
                day: date,
                value: nights
                    .iter()
                    .find(|n| n.day == date)
                    .and_then(|n| usable(n, key)),
            }
        })
        .collect();
    Metric {
        key,
        value,
        quality,
        relation,
        comparison: outlook::comparison(
            key,
            value,
            avg.map(|a| inverse(a, key)),
            quality,
            relation,
        ),
        history,
        baseline: Baseline {
            state: if count < EARLY_COUNT {
                "learning"
            } else if count < ESTABLISHED_COUNT {
                "early"
            } else {
                "established"
            },
            count,
            from,
            to: day - Duration::days(1),
            average: avg.map(|a| inverse(a, key)),
            lower: lower.filter(|_| count >= ESTABLISHED_COUNT),
            upper: upper.filter(|_| count >= ESTABLISHED_COUNT),
        },
        week: Week {
            count: week.len(),
            average: mean(&week)
                .filter(|_| week.len() >= WEEK_COUNT)
                .map(|v| inverse(v, key)),
            previous_average: mean(&previous)
                .filter(|_| week.len() >= WEEK_COUNT && previous.len() >= WEEK_COUNT)
                .map(|v| inverse(v, key)),
        },
    }
}
fn observations(metrics: &[Metric], state: &str) -> Vec<String> {
    if state != "ready" {
        return vec![];
    }
    let mut lines = Vec::new();
    for m in metrics {
        if m.quality != "good" {
            continue;
        }
        if let (Some(value), Some(avg)) = (m.value, m.baseline.average) {
            if m.key == "sleep" && (value - avg).abs() >= 900.0 {
                lines.push((
                    0,
                    format!(
                        "You slept {:.0} minutes {} than your recent average.",
                        (value - avg).abs() / 60.0,
                        if value > avg { "longer" } else { "less" }
                    ),
                ));
            } else if let Some(relation) = m.relation {
                let title = if m.key == "hrv" {
                    "Your HRV"
                } else if m.key == "resting_hr" {
                    "Your resting heart rate"
                } else {
                    continue;
                };
                lines.push((
                    if relation == "similar" { 1 } else { 0 },
                    if relation == "similar" {
                        format!("{title} was within your usual range.")
                    } else {
                        format!("{title} was {relation} than your usual range.")
                    },
                ));
            }
        }
    }
    if lines.is_empty() {
        lines.push((
            0,
            if metrics.iter().any(|m| m.quality == "good") {
                "Your morning measurements are ready."
            } else {
                "Some measurements need a fuller recording."
            }
            .into(),
        ));
    }
    lines.sort_by_key(|(priority, _)| *priority);
    lines.into_iter().take(2).map(|(_, text)| text).collect()
}
fn timing(day: NaiveDate, nights: &[Night]) -> Timing {
    let rows: Vec<_> = nights
        .iter()
        .filter(|n| {
            n.day >= day - Duration::days(6) && n.day <= day && usable(n, "sleep").is_some()
        })
        .collect();
    let same_zone = rows
        .first()
        .is_some_and(|first| rows.iter().all(|r| r.timezone == first.timezone));
    let valid = rows.len() >= WEEK_COUNT && same_zone;
    Timing {
        count: rows.len(),
        asleep_sd_min: valid
            .then(|| clock_sd(&rows.iter().map(|r| r.onset_minute).collect::<Vec<_>>())),
        wake_sd_min: valid
            .then(|| clock_sd(&rows.iter().map(|r| r.wake_minute).collect::<Vec<_>>())),
    }
}
fn clock_sd(values: &[f64]) -> f64 {
    let angle = std::f64::consts::TAU / 1440.0;
    let centre = values
        .iter()
        .map(|v| (v * angle).sin())
        .sum::<f64>()
        .atan2(values.iter().map(|v| (v * angle).cos()).sum::<f64>())
        / angle;
    let unwrapped: Vec<_> = values
        .iter()
        .map(|v| (v - centre + 720.0).rem_euclid(1440.0) - 720.0)
        .collect();
    deviation(&unwrapped, mean(&unwrapped).unwrap_or(0.0))
}
