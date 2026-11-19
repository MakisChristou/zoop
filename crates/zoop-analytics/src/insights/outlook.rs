//! Presentation summaries of the existing descriptive comparisons, not a recovery model.
use super::{ESTABLISHED_COUNT, Metric};
use serde::Serialize;

/// An exact change against the same personal average used by the history chart.
#[derive(Debug, Serialize)]
pub struct Comparison {
    pub delta: f64,
    pub unit: &'static str,
    /// None while learning. These directions describe the display, not health.
    pub signal: Option<&'static str>,
}

/// A categorical presentation of three complete, established comparisons.
#[derive(Debug, Serialize)]
pub struct Outlook {
    pub state: &'static str,
    /// Ordinal display position, not a percentage or physiological score.
    pub level: Option<u8>,
    pub baseline_count: usize,
    pub baseline_required: usize,
}

pub(super) fn comparison(
    key: &str,
    value: Option<f64>,
    average: Option<f64>,
    quality: &str,
    relation: Option<&str>,
) -> Option<Comparison> {
    if quality != "good" {
        return None;
    }
    let (value, average) = value.zip(average)?;
    if !value.is_finite() || !average.is_finite() || average <= 0.0 {
        return None;
    }
    let signal = relation.map(|r| match (key, r) {
        (_, "similar") => "usual",
        ("resting_hr", "lower") | ("sleep" | "hrv", "higher") => "favourable",
        _ => "unfavourable",
    });
    Some(Comparison {
        delta: if key == "hrv" {
            (value / average - 1.0) * 100.0
        } else {
            value - average
        },
        unit: match key {
            "sleep" => "seconds",
            "hrv" => "percent",
            _ => "bpm",
        },
        signal,
    })
}

pub(super) fn summarize(metrics: &[Metric], state: &'static str) -> Outlook {
    let count = metrics.iter().map(|m| m.baseline.count).min().unwrap_or(0);
    let mut result = Outlook {
        state,
        level: None,
        baseline_count: count,
        baseline_required: ESTABLISHED_COUNT,
    };
    if state != "ready" {
        return result;
    }
    if metrics.len() != 3
        || metrics
            .iter()
            .any(|m| m.quality != "good" || m.value.is_none())
    {
        result.state = "limited";
        return result;
    }
    if count < ESTABLISHED_COUNT {
        result.state = "learning";
        return result;
    }
    let signals: Vec<_> = metrics
        .iter()
        .filter_map(|m| m.comparison.as_ref().and_then(|c| c.signal))
        .collect();
    if signals.len() != 3 {
        result.state = "limited";
        return result;
    }
    let favourable = signals.iter().filter(|s| **s == "favourable").count();
    let unfavourable = signals.iter().filter(|s| **s == "unfavourable").count();
    (result.state, result.level) = match (favourable, unfavourable) {
        (0, 0) => ("average", Some(3)),
        (1, 0) => ("good", Some(4)),
        (_, 0) => ("good", Some(5)),
        (0, 1) => ("low", Some(2)),
        (0, _) => ("low", Some(1)),
        _ => ("mixed", None),
    };
    result
}
