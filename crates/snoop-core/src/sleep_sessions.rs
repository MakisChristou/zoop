//! Full local-day sleep sessions. Explicit corrections own their intervals; the
//! detector only sees unclaimed fragments. Existing published sleep/staging methods
//! are reused inside each interval, with missing readings reported independently.
use crate::CoreResult;
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde_json::json;
use snoop_analytics::{
    ALGO_VERSION,
    interval::unclaimed_intervals,
    sleep::{Sample, SleepParams, detect_sleep, night_metrics, selected_window},
    stages::stage_window,
};
use snoop_storage::{PostgresStore, SessionCalculation, SessionDomain, SessionMetrics};

/// Calculates every effective session whose wake-up belongs to this local date.
/// # Errors
/// Storage failure or invalid time zone.
pub(crate) async fn calculate_sleep_day(
    store: &PostgresStore,
    device: &str,
    day: NaiveDate,
    tz: &str,
) -> CoreResult<Vec<SessionCalculation>> {
    let (from, to) = store.local_day_bounds(day, tz).await?;
    let access = store.sessions(SessionDomain::Sleep);
    let fixed = access
        .fixed_sessions(device, from - Duration::hours(24), to + Duration::hours(24))
        .await?;
    let read_from = fixed
        .iter()
        .map(|s| s.start_ts)
        .min()
        .unwrap_or(from)
        .min(from - Duration::hours(24));
    let read_to = fixed
        .iter()
        .map(|s| s.end_ts)
        .max()
        .unwrap_or(to)
        .max(to + Duration::hours(24));
    let rows = store.fetch_samples(device, read_from, read_to).await?;
    let samples: Vec<Sample> = rows.iter().map(crate::night::to_sample).collect();
    let scopes: Vec<_> = access
        .correction_scopes(device, read_from, read_to)
        .await?
        .iter()
        .map(|s| (s.start_ts, s.end_ts))
        .collect();
    let params = SleepParams::default();
    let mut calculated = Vec::new();
    for (a, b) in unclaimed_intervals(read_from, read_to, &scopes) {
        let fragment =
            &samples[samples.partition_point(|s| s.ts < a)..samples.partition_point(|s| s.ts < b)];
        for window in detect_sleep(fragment, &params) {
            let end = window.offset + Duration::seconds(1);
            if end >= from && end < to && end - window.onset <= Duration::hours(24) {
                calculated.push(summarize(&samples, None, window.onset, end, "nap"));
            }
        }
    }
    for row in fixed.iter().filter(|s| s.end_ts >= from && s.end_ts < to) {
        calculated.push(summarize(
            &samples,
            Some(row.id),
            row.start_ts,
            row.end_ts,
            &row.kind,
        ));
    }
    // A user-confirmed main sleep wins; other explicit naps keep their type.
    if !calculated
        .iter()
        .any(|s| s.id.is_some() && s.kind == "main")
        && let Some(main) = calculated
            .iter_mut()
            .filter(|s| s.id.is_none())
            .max_by_key(|s| (s.end_ts - s.start_ts).num_seconds())
    {
        main.kind = "main".into();
    }
    Ok(calculated)
}
fn summarize(
    samples: &[Sample],
    id: Option<i64>,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    kind: &str,
) -> SessionCalculation {
    let window = selected_window(samples, start, end);
    let physiology = night_metrics(samples, &window);
    let (segments, stages) = stage_window(samples, &window);
    let unknown_s = (window.time_in_bed_s - window.coverage_s).max(0);
    let unclassified_s =
        (window.time_in_bed_s - stages.wake_s - stages.light_s - stages.deep_s - stages.rem_s)
            .max(0);
    let covered = window.coverage_s;
    let mut payload = json!({"window":window,"physiology":physiology,"segments":segments,"stages":stages,"algo_version":ALGO_VERSION,"unknown_s":unknown_s,"unclassified_s":unclassified_s,"partial":unknown_s>120});
    payload["window"]["offset"] = json!(end);
    // Unknown periods must not lower an efficiency score as though they were awake.
    payload["efficiency"] = if unknown_s > 120 || covered == 0 {
        json!(null)
    } else {
        json!(window.efficiency)
    };
    SessionCalculation {
        id,
        start_ts: start,
        end_ts: end,
        kind: kind.into(),
        metrics: SessionMetrics {
            sleep: Some(payload),
            coverage_s: Some(covered),
            ..Default::default()
        },
    }
}
