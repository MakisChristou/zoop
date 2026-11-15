//! Descriptive weekly weight feedback, not a fat-loss or energy-expenditure model.
//! Median aggregation limits isolated measurement influence. Weekday-aligned windows
//! address the weekly rhythms reported by Orsama et al., Weight Rhythms, Obesity Facts (2014),
//! doi:10.1159/000356147. Classification tolerances are explicit product heuristics,
//! not thresholds validated by that paper. No calorie prescription is inferred.
use chrono::{Datelike, Duration, NaiveDate};
use serde::Serialize;
use snoop_storage::WeightDay;

const MIN_DAYS: usize = 4;
const MIN_SPAN: i64 = 4;
const MIN_TOLERANCE_KG: f64 = 0.1;
const TARGET_TOLERANCE: f64 = 0.25;
const FLAT_FRACTION: f64 = 0.001;
const EPSILON: f64 = 1e-9;

/// One calendar week; an absent median is missing, never zero.
#[derive(Debug, Serialize)]
pub struct WeightWeek {
    pub start: NaiveDate,
    pub end: NaiveDate,
    pub median_kg: Option<f64>,
    pub count: usize,
    pub eligible: bool,
}
/// Recomputable summary of recorded weights against an explicitly chosen goal.
#[derive(Debug, Serialize)]
pub struct WeightOutlook {
    pub algorithm_version: i32,
    pub start: NaiveDate,
    pub end: NaiveDate,
    pub provisional: bool,
    pub state: &'static str,
    pub reason: &'static str,
    pub median_kg: Option<f64>,
    pub change_kg: Option<f64>,
    pub weekly_loss_kg: f64,
    pub count: usize,
    pub week_number: i64,
    pub weeks: Vec<WeightWeek>,
}
fn median(mut xs: Vec<f64>) -> Option<f64> {
    if xs.is_empty() {
        return None;
    }
    xs.sort_by(f64::total_cmp);
    let n = xs.len();
    Some(if n.is_multiple_of(2) {
        (xs[n / 2 - 1] + xs[n / 2]) / 2.0
    } else {
        xs[n / 2]
    })
}
fn monday(day: NaiveDate) -> NaiveDate {
    day - Duration::days(i64::from(day.weekday().num_days_from_monday()))
}

/// Eight calendar weeks, ending at the latest Sunday (today on Sundays).
/// First-week and sparse windows remain descriptive. Goal changes restart comparisons.
pub fn weight_outlook(
    days: &[WeightDay],
    today: NaiveDate,
    started: NaiveDate,
    pace_started: NaiveDate,
    target: f64,
) -> WeightOutlook {
    let current = monday(today);
    let latest = if today.weekday() == chrono::Weekday::Sun || pace_started >= current {
        current
    } else {
        current - Duration::days(7)
    };
    let mut weeks = Vec::new();
    for offset in (0..8).rev() {
        let start = latest - Duration::days(offset * 7);
        let end = start + Duration::days(6);
        // Deduplicate defensively; storage already selects one source-owned reading/day.
        let mut daily = std::collections::BTreeMap::new();
        for d in days.iter().filter(|d| {
            d.day >= start
                && d.day <= end
                && d.day <= today
                && d.day >= pace_started
                && d.kg.is_finite()
                && (20.0..=400.0).contains(&d.kg)
        }) {
            daily.entry(d.day).or_insert(d.kg);
        }
        let count = daily.len();
        let span = daily
            .keys()
            .next()
            .zip(daily.keys().next_back())
            .map_or(0, |(a, b)| (*b - *a).num_days());
        weeks.push(WeightWeek {
            start,
            end,
            median_kg: median(daily.values().copied().collect()),
            count,
            eligible: count >= MIN_DAYS
                && span >= MIN_SPAN
                && start >= pace_started
                && end <= today,
        });
    }
    let a = &weeks[5];
    let b = &weeks[6];
    let c = &weeks[7];
    let starting = (today - pace_started).num_days() < 7 || latest < pace_started;
    let change = if b.eligible && c.eligible {
        b.median_kg.zip(c.median_kg).map(|(x, y)| y - x)
    } else {
        None
    };
    let tolerance = MIN_TOLERANCE_KG
        .max(target * TARGET_TOLERANCE)
        .min(target * 0.5);
    let slow = |loss: f64| loss + EPSILON < target - tolerance;
    let fast = |loss: f64| loss - EPSILON > target + tolerance;
    let (state, reason) = if starting {
        ("starting", "first_week")
    } else if let Some(change) = change {
        let loss = -change;
        let previous = if a.eligible {
            a.median_kg.zip(b.median_kg).map(|(x, y)| x - y)
        } else {
            None
        };
        let flat = c.median_kg.unwrap_or(0.0) * FLAT_FRACTION;
        if previous.is_some_and(|p| p.abs() <= flat && loss.abs() <= flat)
            && slow(loss)
            && slow(previous.unwrap_or(loss))
        {
            ("possible_stall", "three_flat_weeks")
        } else if previous
            .is_some_and(|p| p * loss < 0.0 && p.abs() > tolerance && loss.abs() > tolerance)
        {
            ("unclear", "conflicting_weeks")
        } else if previous.is_some_and(|p| slow(p) && slow(loss)) {
            ("below_pace", "two_slow_weeks")
        } else if previous.is_some_and(|p| fast(p) && fast(loss)) {
            ("faster", "two_fast_weeks")
        } else if slow(loss) {
            ("slower_week", "one_slow_week")
        } else if fast(loss) {
            ("faster_week", "one_fast_week")
        } else {
            ("on_pace", "within_target")
        }
    } else {
        ("insufficient", "sparse_weeks")
    };
    WeightOutlook {
        algorithm_version: 1,
        start: c.start,
        end: c.end,
        provisional: c.end >= today,
        state,
        reason,
        median_kg: c.median_kg,
        change_kg: change,
        weekly_loss_kg: target,
        count: c.count,
        week_number: ((c.start - started).num_days() / 7 + 1).max(1),
        weeks,
    }
}

#[cfg(test)]
#[path = "weight_outlook/tests.rs"]
mod tests;
