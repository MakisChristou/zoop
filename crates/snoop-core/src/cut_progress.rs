//! Calendar arithmetic and observed weight change, not a prediction of physiology.
//! Uses the same descriptive median aggregation documented in weight_outlook.
use chrono::{Duration, NaiveDate};
use serde::Serialize;
use snoop_storage::WeightDay;

/// Progress remains separate from weekly pace eligibility.
#[derive(Debug, Serialize)]
pub struct CutProgress {
    pub finish_date: Option<NaiveDate>,
    pub weeks_remaining: Option<i64>,
    pub completed: bool,
    pub starting_weight_kg: Option<f64>,
    pub current_weight_kg: Option<f64>,
    pub total_lost_kg: Option<f64>,
    pub target_weight_kg: Option<f64>,
}
fn daily(
    days: &[WeightDay],
    from: NaiveDate,
    to: NaiveDate,
) -> std::collections::BTreeMap<NaiveDate, f64> {
    let mut result = std::collections::BTreeMap::new();
    for d in days.iter().filter(|d| {
        d.day >= from && d.day <= to && d.kg.is_finite() && (20.0..=400.0).contains(&d.kg)
    }) {
        result.entry(d.day).or_insert(d.kg);
    }
    result
}
fn median(values: impl Iterator<Item = f64>) -> Option<f64> {
    let mut xs: Vec<_> = values.collect();
    if xs.is_empty() {
        return None;
    }
    xs.sort_by(f64::total_cmp);
    let n = xs.len();
    Some((xs[(n - 1) / 2] + xs[n / 2]) / 2.0)
}
/// Baseline: prior seven calendar days including start; if absent, first reading
/// within seven days after start. Current: median of last seven days, capped at finish.
/// Missing or stale observations stay unknown. Negative loss honestly means a gain.
pub fn cut_progress(
    baseline: &[WeightDay],
    recent: &[WeightDay],
    today: NaiveDate,
    started: NaiveDate,
    finish: Option<NaiveDate>,
    rate: f64,
) -> CutProgress {
    let as_of = finish.map_or(today, |end| end.min(today));
    let prior = daily(baseline, started - Duration::days(6), started.min(as_of));
    let initial = median(prior.values().copied()).or_else(|| {
        daily(baseline, started, (started + Duration::days(7)).min(as_of))
            .values()
            .next()
            .copied()
    });
    let current = median(
        daily(recent, (as_of - Duration::days(6)).max(started), as_of)
            .values()
            .copied(),
    );
    let target = finish.zip(initial).and_then(|(end, weight)| {
        let duration = (end - started).num_days();
        let target = weight - rate * duration as f64 / 7.0;
        (duration > 0 && rate.is_finite() && rate > 0.0 && (20.0..=400.0).contains(&target))
            .then_some(target)
    });
    CutProgress {
        finish_date: finish,
        weeks_remaining: finish.map(|end| ((end - today).num_days().max(0) + 6) / 7),
        completed: finish.is_some_and(|end| today > end),
        starting_weight_kg: initial,
        current_weight_kg: current,
        total_lost_kg: initial.zip(current).map(|(start, now)| start - now),
        target_weight_kg: target,
    }
}

#[cfg(test)]
#[path = "cut_progress/tests.rs"]
mod tests;
