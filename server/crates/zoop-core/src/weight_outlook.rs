//! Descriptive weekly weight feedback, not a fat-loss or energy-expenditure model.
//! Median aggregation limits isolated measurement influence. Weekday-aligned windows
//! address the weekly rhythms reported by Orsama et al., Weight Rhythms, Obesity Facts (2014),
//! doi:10.1159/000356147. Classification tolerances are explicit product heuristics,
//! not thresholds validated by that paper. No calorie prescription is inferred.
use chrono::{Datelike, Duration, NaiveDate};
use serde::Serialize;
use zoop_storage::WeightDay;

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
    pub trend_kg_per_week: Option<f64>,
    pub maintenance_lower_kg: Option<f64>,
    pub maintenance_upper_kg: Option<f64>,
    pub algorithm_version: i32,
    pub progress: Option<crate::CutProgress>,
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
        trend_kg_per_week: None,
        maintenance_lower_kg: None,
        maintenance_upper_kg: None,
        algorithm_version: 1,
        progress: None,
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

/// Descriptive weekly statistics with explicit product thresholds, not physiology.
/// Weekly alignment: Orsama et al. (2014), doi:10.1159/000356147.
/// Median resistance: NIST Dataplot, MEDIAN CONFIDENCE LIMITS.
/// The persistence thresholds are not clinically validated diagnostic boundaries.
pub fn phase_outlook(
    days: &[WeightDay],
    today: NaiveDate,
    started: NaiveDate,
    pace_started: NaiveDate,
    goal: &zoop_storage::WeightGoal,
) -> WeightOutlook {
    let mut result = weight_outlook(days, today, started, pace_started, goal.weekly_loss_kg);
    result.algorithm_version = 2;
    result.weeks = phase_weeks(days, today, started, pace_started, result.start);
    let maintenance = goal.phase == "maintenance";
    let reference = goal.maintenance_reference_kg;
    result.maintenance_lower_kg = reference.map(|r| r * (1.0 - goal.maintenance_range_pct / 100.0));
    result.maintenance_upper_kg = reference.map(|r| r * (1.0 + goal.maintenance_range_pct / 100.0));
    let n = result.weeks.len();
    let a = &result.weeks[n - 3];
    let b = &result.weeks[n - 2];
    let c = &result.weeks[n - 1];
    result.median_kg = c.median_kg;
    result.count = c.count;
    result.state = "building_trend";
    result.reason = "three_eligible_weeks";
    if !(a.eligible && b.eligible && c.eligible) {
        return result;
    }
    let (Some(a), Some(b), Some(c)) = (a.median_kg, b.median_kg, c.median_kg) else {
        return result;
    };
    let d1 = b - a;
    let d2 = c - b;
    let trend = (c - a) / 2.0;
    result.trend_kg_per_week = Some(trend);
    let target = match goal.phase.as_str() {
        "bulk" => goal.weekly_loss_kg,
        "maintenance" => 0.0,
        _ => -goal.weekly_loss_kg,
    };
    let tolerance = if maintenance {
        let Some(reference) = reference else {
            return result;
        };
        reference * FLAT_FRACTION
    } else {
        MIN_TOLERANCE_KG
            .max(target.abs() * TARGET_TOLERANCE)
            .min(target.abs() * 0.5)
    };
    if maintenance {
        if result
            .maintenance_upper_kg
            .is_some_and(|upper| b > upper && c > upper)
        {
            result.state = "above_range";
            result.reason = "two_weeks_above_range";
            return result;
        }
        if result
            .maintenance_lower_kg
            .is_some_and(|lower| b < lower && c < lower)
        {
            result.state = "below_range";
            result.reason = "two_weeks_below_range";
            return result;
        }
    }
    let side = |rate: f64| -> i32 {
        if rate - target > tolerance + EPSILON {
            1
        } else if rate - target < -tolerance - EPSILON {
            -1
        } else {
            0
        }
    };
    let direction = side(trend);
    if direction == 0 {
        let outside = maintenance
            && (result.maintenance_lower_kg.is_some_and(|lo| c < lo)
                || result.maintenance_upper_kg.is_some_and(|hi| c > hi));
        result.state = if outside {
            "watching"
        } else if maintenance {
            "stable"
        } else {
            "on_pace"
        };
        result.reason = if outside {
            "one_week_outside_range"
        } else {
            "within_target"
        };
        return result;
    }
    let previous = &result.weeks[n - 4];
    let persistent = (side(d1) == direction && side(d2) == direction)
        || (previous.eligible
            && previous
                .median_kg
                .is_some_and(|p| side((b - p) / 2.0) == direction));
    if !persistent {
        result.state = "watching";
        result.reason = "unconfirmed_change";
        return result;
    }
    result.reason = "persistent_trend";
    result.state = if maintenance {
        if direction > 0 {
            "drifting_up"
        } else {
            "drifting_down"
        }
    } else {
        let slow = (target < 0.0 && direction > 0) || (target > 0.0 && direction < 0);
        let initial = days
            .iter()
            .filter(|d| {
                d.day >= started
                    && d.day <= today
                    && d.kg.is_finite()
                    && (20.0..=400.0).contains(&d.kg)
            })
            .min_by_key(|d| d.day)
            .map_or(c, |d| d.kg);
        if slow && d1.abs() <= initial * FLAT_FRACTION && d2.abs() <= initial * FLAT_FRACTION {
            "possible_stall"
        } else if slow {
            "below_pace"
        } else {
            "above_pace"
        }
    };
    result
}

#[cfg(test)]
#[path = "weight_outlook/phase_tests.rs"]
mod phase_tests;

fn phase_weeks(
    days: &[WeightDay],
    today: NaiveDate,
    started: NaiveDate,
    pace: NaiveDate,
    latest: NaiveDate,
) -> Vec<WeightWeek> {
    let first = monday(started).min(latest - Duration::weeks(7));
    let mut groups =
        std::collections::BTreeMap::<NaiveDate, std::collections::BTreeMap<NaiveDate, f64>>::new();
    for d in days.iter().filter(|d| {
        d.day >= started && d.day <= today && d.kg.is_finite() && (20.0..=400.0).contains(&d.kg)
    }) {
        groups
            .entry(monday(d.day))
            .or_default()
            .entry(d.day)
            .or_insert(d.kg);
    }
    (0..=(latest - first).num_weeks())
        .map(|i| {
            let start = first + Duration::weeks(i);
            let end = start + Duration::days(6);
            let rows = groups.remove(&start).unwrap_or_default();
            let count = rows.len();
            let span = rows
                .keys()
                .next()
                .zip(rows.keys().next_back())
                .map_or(0, |(a, b)| (*b - *a).num_days());
            WeightWeek {
                start,
                end,
                median_kg: median(rows.into_values().collect()),
                count,
                eligible: count >= MIN_DAYS && span >= MIN_SPAN && start >= pace && end <= today,
            }
        })
        .collect()
}
