//! Daily workout detection worker and the on-demand entry points behind
//! `zoop analyze-workouts` and the steps endpoint.
//!
//! A day is a local calendar day in the device profile's time zone (UTC when there is
//! no profile). Samples two hours either side are read as context so a session that
//! straddles midnight is detected whole, and only sessions starting inside the day are
//! stored. Results are keyed by `WORKOUT_ALGO_VERSION`;
//! time-aware profile snapshots and independent labels keep historical inputs and
//! corrections stable while new method versions are computed.

use chrono::{DateTime, Datelike, Duration as ChronoDuration, NaiveDate, Utc};
use serde::Serialize;
use tracing::{debug, info};
use zoop_analytics::WORKOUT_ALGO_VERSION;
use zoop_analytics::bouts::{ActivitySample, Bout, detect_bouts};
use zoop_analytics::energy::{Body, Sex};
use zoop_analytics::interval::{summarize_interval, unclaimed_intervals};
use zoop_analytics::workouts::{
    DayLoad, Physiology, Workout, WorkoutParams, day_load, detect_workouts,
};
use zoop_analytics::zones;
use zoop_storage::{PostgresStore, ProfileRow, SampleFull, SessionCalculation, SessionMetrics};

use crate::CoreResult;

/// Hours of samples read either side of the day so sessions across midnight are whole.
const CONTEXT_HOURS: i64 = 2;

/// Window over which the strap's own maximal heart rate is observed.
const OBSERVED_HR_MAX_DAYS: i32 = 90;
/// Resting heart rate assumed until a night has been analysed.
const DEFAULT_RESTING_HR: f64 = 60.0;
/// Age assumed for the maximal-heart-rate prediction until a birth year is entered.
/// A few days of strap data would otherwise set the maximum far too low, turning
/// ordinary mornings into sessions; the population prediction is the safer floor.
const DEFAULT_AGE_YEARS: f64 = 40.0;
const DEFAULT_TZ: &str = "UTC";

/// Everything computed for one day, as printed by the CLI.
#[derive(Debug, Clone, Serialize)]
pub struct DayResult {
    pub day: NaiveDate,
    pub tz: String,
    pub physiology: Physiology,
    pub params: WorkoutParams,
    pub workouts: Vec<Workout>,
    pub load: DayLoad,
    pub kcal: Option<f64>,
    pub samples: usize,
    pub has_hr: bool,
    #[serde(skip)]
    pub sessions: Vec<SessionCalculation>,
}

/// Steps through one local day, for the detailed steps screen.
#[derive(Debug, Clone, Serialize)]
pub struct DaySteps {
    pub day: NaiveDate,
    /// Counter increments per local hour, 0–23.
    pub hours: Vec<i64>,
    /// The same, restricted to seconds the strap labelled walking or running.
    pub walking_hours: Vec<i64>,
    pub total: i64,
    pub walking: i64,
    pub bouts: Vec<BoutOut>,
}

/// A walking bout with its cadence.
#[derive(Debug, Clone, Serialize)]
pub struct BoutOut {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub duration_s: i64,
    pub steps: i64,
    pub cadence_spm: f64,
}

impl From<Bout> for BoutOut {
    fn from(bout: Bout) -> Self {
        Self {
            cadence_spm: bout.cadence_spm(),
            start: bout.start,
            end: bout.end,
            duration_s: bout.duration_s,
            steps: bout.steps,
        }
    }
}

/// Queues a durable recalculation and returns a preview. `day` defaults to today in
/// the profile's zone. Returns `None` when there was no heart-rate data to work from.
pub async fn analyze_day(
    store: &PostgresStore,
    device_id: &str,
    day: Option<NaiveDate>,
) -> CoreResult<Option<DayResult>> {
    let profile = store.get_profile(device_id).await?;
    let tz = profile
        .as_ref()
        .map_or(DEFAULT_TZ, |p| p.tz.as_str())
        .to_owned();
    let day = match day {
        Some(day) => day,
        None => store.local_today(&tz).await?,
    };
    store
        .request_analysis(device_id, "workout", day, &tz, WORKOUT_ALGO_VERSION, true)
        .await?;
    let (_, to) = store.local_day_bounds(day, &tz).await?;
    let profile = store.profile_at(device_id, to).await?;
    calculate_day(store, device_id, profile.as_ref(), &tz, day).await
}

pub async fn calculate_day(
    store: &PostgresStore,
    device_id: &str,
    profile: Option<&ProfileRow>,
    tz: &str,
    day: NaiveDate,
) -> CoreResult<Option<DayResult>> {
    let (from, to) = store.local_day_bounds(day, tz).await?;
    let context = ChronoDuration::hours(CONTEXT_HOURS);
    let fixed = store.fixed_sessions(device_id, from, to).await?;
    let read_from = fixed
        .iter()
        .map(|w| w.start_ts - ChronoDuration::seconds(1))
        .fold(from - context, std::cmp::min);
    let read_to = fixed
        .iter()
        .map(|w| w.end_ts)
        .fold(to + context, std::cmp::max);
    let scopes: Vec<_> = store
        .correction_scopes(device_id, read_from, read_to)
        .await?
        .into_iter()
        .map(|s| (s.start_ts, s.end_ts))
        .collect();
    let rows = store.fetch_samples(device_id, read_from, read_to).await?;
    let mut samples: Vec<ActivitySample> = rows.iter().map(to_activity_sample).collect();
    // Explicit sleep ownership replaces the raw flag within its scope. Active
    // recorded sleep is still masked below; removed false sleep cannot return via
    // the detector's independent raw-band fallback.
    let sleep_scopes = store
        .sessions(zoop_storage::SessionDomain::Sleep)
        .correction_scopes(device_id, read_from, read_to)
        .await?;
    for sample in &mut samples {
        if sample.band_state == 2
            && sleep_scopes
                .iter()
                .any(|s| s.start_ts <= sample.ts && sample.ts < s.end_ts)
        {
            sample.band_state = 0;
        }
    }
    let sleep = store.sleep_windows(device_id, read_from, read_to).await?;

    if samples.is_empty() && fixed.is_empty() {
        debug!(device_id, %day, "no sample data; skipping");
        return Ok(None);
    }
    let physiology = physiology_for_day(store, device_id, profile, day, to).await?;
    let params = WorkoutParams::default();

    let detected = detect_workouts(&samples, &sleep, &physiology, &params);
    let workouts: Vec<Workout> = detected
        .iter()
        .filter(|w| w.start >= from && w.start < to)
        .cloned()
        .collect();
    let mut effective = Vec::new();
    for candidate in &detected {
        let fragments = unclaimed_intervals(candidate.start, candidate.end, &scopes);
        for (a, b) in fragments {
            let candidates = if a == candidate.start && b == candidate.end {
                vec![candidate.clone()]
            } else {
                let slice = &samples
                    [samples.partition_point(|s| s.ts < a)..samples.partition_point(|s| s.ts < b)];
                detect_workouts(slice, &sleep, &physiology, &params)
            };
            for w in candidates {
                let start = w.start.max(a);
                let end = w.end.min(b);
                let min_minutes = if w.kind == zoop_analytics::workouts::WorkoutKind::Walk {
                    params.min_walk_min
                } else {
                    params.min_session_min
                };
                if (end - start).num_seconds() < min_minutes * 60 {
                    continue;
                }
                effective.push(SessionCalculation {
                    id: None,
                    start_ts: start,
                    end_ts: end,
                    kind: w.kind.as_str().to_owned(),
                    metrics: metrics(&samples, start, end, &physiology),
                });
            }
        }
    }
    let mut physiology_by_day = std::collections::BTreeMap::from([(day, physiology)]);
    for w in &fixed {
        let session_day = store.local_date_at(w.start_ts, tz).await?;
        if let std::collections::btree_map::Entry::Vacant(entry) =
            physiology_by_day.entry(session_day)
        {
            let (_, cutoff) = store.local_day_bounds(session_day, tz).await?;
            let past_profile = store.profile_at(device_id, cutoff).await?;
            let past =
                physiology_for_day(store, device_id, past_profile.as_ref(), session_day, cutoff)
                    .await?;
            entry.insert(past);
        }
        let session_physiology = physiology_by_day.get(&session_day).unwrap_or(&physiology);
        effective.push(SessionCalculation {
            id: Some(w.id),
            start_ts: w.start_ts,
            end_ts: w.end_ts,
            kind: w.kind.clone(),
            metrics: metrics(&samples, w.start_ts, w.end_ts, session_physiology),
        });
    }
    // Daily workout calories are assigned by sample time, including sessions that
    // began yesterday. Corrected intervals are disjoint, so no second is counted twice.
    let mut kcal = Some(0.0);
    for w in effective
        .iter()
        .filter(|w| w.start_ts < to && w.end_ts > from)
    {
        let session_day = store.local_date_at(w.start_ts, tz).await?;
        if let std::collections::btree_map::Entry::Vacant(entry) =
            physiology_by_day.entry(session_day)
        {
            let (_, cutoff) = store.local_day_bounds(session_day, tz).await?;
            let past_profile = store.profile_at(device_id, cutoff).await?;
            let past =
                physiology_for_day(store, device_id, past_profile.as_ref(), session_day, cutoff)
                    .await?;
            entry.insert(past);
        }
        let p = physiology_by_day.get(&session_day).unwrap_or(&physiology);
        let part = summarize_interval(&samples, w.start_ts.max(from), w.end_ts.min(to), p).kcal;
        kcal = kcal.zip(part).map(|(sum, part)| sum + part);
    }
    let sessions = effective
        .into_iter()
        .filter(|w| w.start_ts >= from && w.start_ts < to)
        .collect();
    let day_from = samples.partition_point(|s| s.ts < from);
    let day_to = samples.partition_point(|s| s.ts < to);
    let load = day_load(&samples[day_from..day_to], &sleep, &physiology);
    let has_hr = samples[day_from..day_to].iter().any(|s| s.hr.is_some());

    info!(device_id, %day, sessions = workouts.len(), load = format!("{:.1}", load.load), "day calculated");
    Ok(Some(DayResult {
        day,
        tz: tz.to_owned(),
        physiology,
        params,
        workouts,
        load,
        kcal,
        samples: day_to - day_from,
        has_hr,
        sessions,
    }))
}

/// Hourly steps and walking bouts for one local day.
pub async fn day_steps(
    store: &PostgresStore,
    device_id: &str,
    day: NaiveDate,
    tz: &str,
) -> CoreResult<DaySteps> {
    let (from, to) = store.local_day_bounds(day, tz).await?;
    let hourly = store.hourly_steps(device_id, day, tz).await?;
    let mut hours = vec![0_i64; 24];
    let mut walking_hours = vec![0_i64; 24];
    for h in hourly {
        if let Some(slot) = usize::try_from(h.hour).ok().filter(|&i| i < 24) {
            hours[slot] = h.steps;
            walking_hours[slot] = h.walking;
        }
    }
    let rows = store.fetch_samples(device_id, from, to).await?;
    let samples: Vec<ActivitySample> = rows.iter().map(to_activity_sample).collect();
    let bouts = detect_bouts(&samples)
        .into_iter()
        .map(BoutOut::from)
        .collect();
    Ok(DaySteps {
        day,
        total: hours.iter().sum(),
        walking: walking_hours.iter().sum(),
        hours,
        walking_hours,
        bouts,
    })
}

fn body_of(profile: Option<&ProfileRow>, age: Option<f64>) -> Option<Body> {
    let profile = profile?;
    let sex = profile.sex.as_deref().and_then(Sex::parse)?;
    Some(Body {
        sex,
        age_years: age?,
        weight_kg: f64::from(profile.weight_kg?),
    })
}

fn to_activity_sample(row: &SampleFull) -> ActivitySample {
    ActivitySample {
        ts: row.ts,
        hr: row.hr.and_then(|h| u8::try_from(h).ok()).filter(|h| *h > 0),
        steps: row.steps,
        activity: row.activity.and_then(|a| u8::try_from(a).ok()),
        motion_g: row.accel_dyn_g,
        band_state: u8::try_from(row.band_state).unwrap_or(0),
    }
}

fn metrics(
    samples: &[ActivitySample],
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    physiology: &Physiology,
) -> SessionMetrics {
    let m = summarize_interval(samples, start, end, physiology);
    SessionMetrics {
        sleep: None,
        load: m.load,
        avg_hr: m.avg_hr,
        max_hr: m.max_hr.map(i16::from),
        trimp: m.trimp,
        zones_min: m.zones.map(|z| z.minutes().to_vec()),
        kcal: m.kcal,
        steps: m.steps,
        coverage_s: Some(m.coverage_s),
        hr_coverage_s: Some(m.hr_coverage_s),
    }
}

async fn physiology_for_day(
    store: &PostgresStore,
    device: &str,
    profile: Option<&ProfileRow>,
    day: NaiveDate,
    cutoff: DateTime<Utc>,
) -> CoreResult<Physiology> {
    let age = profile
        .and_then(|p| p.birth_year)
        .map(|year| f64::from(day.year() - i32::from(year)));
    let observed = store
        .observed_hr_max_at(device, OBSERVED_HR_MAX_DAYS, cutoff)
        .await?;
    Ok(Physiology {
        hr_max: zones::hr_max(Some(age.unwrap_or(DEFAULT_AGE_YEARS)), observed)
            .unwrap_or_else(|| zones::predicted_hr_max(DEFAULT_AGE_YEARS)),
        resting_hr: store
            .resting_hr_at(device, cutoff)
            .await?
            .unwrap_or(DEFAULT_RESTING_HR),
        body: body_of(profile, age),
    })
}
