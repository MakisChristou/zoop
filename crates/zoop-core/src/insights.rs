//! Adapts effective sleep summaries to independent, quality-gated comparisons.
use crate::CoreResult;
use chrono::{Duration, NaiveDate};
use zoop_analytics::{
    ALGO_VERSION,
    insights::{self, MorningInsights, Night, Reading},
};
use zoop_storage::{InsightNight, InsightSnapshot, PostgresStore};
const MAX_UNKNOWN_SLEEP_SECONDS: f64 = 120.0;
const MIN_CARDIAC_COVERAGE: f64 = 0.90;
const MIN_HRV_WINDOWS: f64 = 6.0;
const MIN_HRV_WINDOW_FRACTION: f64 = 0.50;
/// Reads and calculates one brief without changing raw data or stored projections.
/// # Errors
/// Storage failure while obtaining the consistent snapshot.
pub async fn morning_insights(
    store: &PostgresStore,
    device: &str,
    day: NaiveDate,
    tz: &str,
) -> CoreResult<Option<MorningInsights>> {
    let Some(snapshot) = store
        .insight_snapshot(
            device,
            day - Duration::days(insights::BASELINE_DAYS),
            day,
            tz,
            ALGO_VERSION,
        )
        .await?
    else {
        return Ok(None);
    };
    Ok(Some(from_snapshot(day, tz, snapshot)))
}
pub(crate) fn from_snapshot(
    day: NaiveDate,
    tz: &str,
    snapshot: InsightSnapshot,
) -> MorningInsights {
    let mut recovery_nights = Vec::new();
    for row in &snapshot.nights {
        let mut night = input_ref(row);
        // Old measurement versions cannot supply evidence for the current formula.
        if row
            .metrics
            .pointer("/sleep/algo_version")
            .and_then(serde_json::Value::as_i64)
            != Some(i64::from(ALGO_VERSION))
        {
            if row.day != day {
                continue;
            }
            night.hrv.quality = "limited";
        }
        recovery_nights.push(night.clone());
        if row.day_count > 1 {
            recovery_nights.push(night);
        }
    }
    let nights = snapshot.nights.iter().map(input_ref).collect::<Vec<_>>();
    let mut brief = insights::calculate(day, tz, &nights, snapshot.pending);
    brief.recovery =
        zoop_analytics::recovery::calculate(day, tz, &recovery_nights, snapshot.pending);
    brief
}
pub(crate) fn input_ref(row: &InsightNight) -> Night {
    let metric = |key: &str| {
        row.metrics
            .pointer(key)
            .and_then(serde_json::Value::as_f64)
            .filter(|v| v.is_finite())
    };
    let duration = row.duration_s as f64;
    let coverage = metric("/sleep/window/coverage_s").unwrap_or(0.0);
    let windows = metric("/sleep/physiology/hrv_windows").unwrap_or(0.0);
    let read = |value: Option<f64>, valid: bool| Reading {
        value: value.filter(|v| *v > 0.0),
        quality: if value.is_none_or(|v| v <= 0.0) {
            "missing"
        } else if valid {
            "good"
        } else {
            "limited"
        },
    };
    Night {
        day: row.day,
        id: row.id,
        revision: row.revision,
        state: if row.pending {
            "updating"
        } else if !row.complete {
            "awaiting_sync"
        } else {
            "ready"
        },
        sleep: read(
            metric("/sleep/window/asleep_s"),
            duration > 0.0 && duration - coverage <= MAX_UNKNOWN_SLEEP_SECONDS,
        ),
        hrv: read(
            metric("/sleep/physiology/hrv_rmssd_ms"),
            duration > 0.0
                && coverage / duration >= MIN_CARDIAC_COVERAGE
                && windows
                    >= MIN_HRV_WINDOWS.max((duration / 300.0).ceil() * MIN_HRV_WINDOW_FRACTION),
        ),
        resting_hr: read(
            metric("/sleep/physiology/resting_hr"),
            duration > 0.0 && row.hr_samples as f64 / duration >= MIN_CARDIAC_COVERAGE,
        ),
        onset_minute: row.onset_minute,
        wake_minute: row.wake_minute,
        timezone: row.timezone.clone(),
    }
}
