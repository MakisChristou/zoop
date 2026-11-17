//! Calendar arithmetic and observed weight change, not a prediction of physiology.
//! Progress uses first/latest canonical cut weigh-ins; weekly pace retains medians.
use chrono::NaiveDate;
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
/// First and latest real daily readings from the cut's local start day through
/// today (or finish). Pre-cut and future readings cannot influence progress.
/// A single reading means zero observed change; missing readings stay unknown.
pub fn cut_progress(
    readings: &[WeightDay],
    today: NaiveDate,
    started: NaiveDate,
    finish: Option<NaiveDate>,
    rate: f64,
) -> CutProgress {
    let as_of = finish.map_or(today, |end| end.min(today));
    let observed = daily(readings, started, as_of);
    let initial = observed.first_key_value().map(|(_, kg)| *kg);
    let current = observed.last_key_value().map(|(_, kg)| *kg);
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
