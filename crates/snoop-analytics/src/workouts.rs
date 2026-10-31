//! Session detection: walks, resistance training and other exertion.
//!
//! A minute is "exerting" when its mean heart rate reaches a fraction of heart-rate
//! reserve (Karvonen 1957; see `zones`), 40 % by default, which is the lower bound of
//! moderate intensity in the ACSM position stand (Garber et al. 2011, "Quantity and
//! quality of exercise for developing and maintaining cardiorespiratory,
//! musculoskeletal, and neuromotor fitness in apparently healthy adults", Med Sci
//! Sports Exerc 43(7): 1334–1359), or when the strap labels most of it as walking or
//! running. Exerting minutes are chained across rests of up to five minutes, which
//! keeps the recovery between sets inside one resistance session. Minutes the strap
//! flags as sleep, or that fall in a detected sleep window, never exert.
//!
//! Sessions are typed by how much of them was ambulatory: mostly walking is a walk,
//! hardly any is resistance training, and the rest is left as unlabelled activity for
//! the user to name. That bias towards resistance training reflects the one kind of
//! non-ambulatory exertion this project's users do; the label is editable. Zones,
//! training impulse and load come from `zones`, calories from `energy`.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::bouts::{ActivitySample, step_increments, steps_between};
use crate::energy::{Body, kcal_over_seconds};
use crate::zones::{ZoneSeconds, hr_reserve_threshold, load};

/// Tunables, exposed so they can be reported next to results.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct WorkoutParams {
    /// Non-exerting minutes up to this long stay inside a session.
    pub rest_gap_min: i64,
    /// Shortest walk worth a session.
    pub min_walk_min: i64,
    /// Shortest non-walking session.
    pub min_session_min: i64,
    /// Fraction of heart-rate reserve at which a minute exerts.
    pub exert_hrr_fraction: f64,
    /// Fraction of a minute's seconds labelled walking for the minute to exert.
    pub walk_minute_fraction: f64,
    /// Sessions at least this ambulatory are walks.
    pub walk_session_fraction: f64,
    /// Sessions at most this ambulatory are resistance training.
    pub resistance_walk_fraction: f64,
    /// Sessions whose minutes exert less often than this are chance spikes, dropped.
    pub min_exerting_fraction: f64,
}

impl Default for WorkoutParams {
    fn default() -> Self {
        Self {
            rest_gap_min: 5,
            min_walk_min: 10,
            min_session_min: 20,
            exert_hrr_fraction: 0.4,
            walk_minute_fraction: 0.5,
            walk_session_fraction: 0.6,
            resistance_walk_fraction: 0.2,
            min_exerting_fraction: 0.5,
        }
    }
}

/// What the detector knows about the person: zone bounds and, optionally, the body
/// the calorie equations need.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Physiology {
    pub hr_max: f64,
    pub resting_hr: f64,
    pub body: Option<Body>,
}

/// Session type. The detector assigns one; the user may overrule it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WorkoutKind {
    Walk,
    Resistance,
    /// Exertion the detector could not type; shown to the user to label.
    Activity,
}

impl WorkoutKind {
    /// Stored representation.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Walk => "walk",
            Self::Resistance => "resistance",
            Self::Activity => "activity",
        }
    }

    /// Parses the stored representation.
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "walk" => Some(Self::Walk),
            "resistance" => Some(Self::Resistance),
            "activity" => Some(Self::Activity),
            _ => None,
        }
    }
}

/// A detected session with its summary.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Workout {
    pub start: DateTime<Utc>,
    /// Exclusive.
    pub end: DateTime<Utc>,
    pub kind: WorkoutKind,
    pub duration_s: i64,
    pub avg_hr: f64,
    pub max_hr: u8,
    pub zones: ZoneSeconds,
    pub trimp: f64,
    pub load: f64,
    /// Present only when the physiology carried a body.
    pub kcal: Option<f64>,
    pub steps: i64,
    /// Fraction of the session's seconds the strap labelled walking or running.
    pub walk_fraction: f64,
}

/// Load accumulated over a whole day's awake time, sessions or not.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DayLoad {
    pub zones: ZoneSeconds,
    pub trimp: f64,
    pub load: f64,
    /// Awake seconds with a heart rate reading.
    pub awake_s: u32,
}

const SECONDS_PER_MINUTE: i64 = 60;

struct Minute {
    start: DateTime<Utc>,
    hr_sum: f64,
    hr_n: u32,
    walk_s: u32,
    asleep_s: u32,
    n: u32,
}

impl Minute {
    fn mean_hr(&self) -> Option<f64> {
        (self.hr_n > 0).then(|| self.hr_sum / f64::from(self.hr_n))
    }

    fn exerting(&self, threshold_hr: f64, params: &WorkoutParams) -> bool {
        if self.asleep_s * 2 >= self.n {
            return false;
        }
        let walking = f64::from(self.walk_s) / f64::from(self.n) >= params.walk_minute_fraction;
        walking || self.mean_hr().is_some_and(|hr| hr >= threshold_hr)
    }
}

fn minute_start(ts: DateTime<Utc>) -> DateTime<Utc> {
    ts - Duration::seconds(ts.timestamp().rem_euclid(SECONDS_PER_MINUTE))
}

fn in_sleep(ts: DateTime<Utc>, sleep: &[(DateTime<Utc>, DateTime<Utc>)]) -> bool {
    sleep
        .iter()
        .any(|&(onset, offset)| onset <= ts && ts < offset)
}

fn minutes(samples: &[ActivitySample], sleep: &[(DateTime<Utc>, DateTime<Utc>)]) -> Vec<Minute> {
    let mut out: Vec<Minute> = Vec::new();
    for sample in samples {
        let start = minute_start(sample.ts);
        if out.last().is_none_or(|m| m.start != start) {
            out.push(Minute {
                start,
                hr_sum: 0.0,
                hr_n: 0,
                walk_s: 0,
                asleep_s: 0,
                n: 0,
            });
        }
        let Some(minute) = out.last_mut() else {
            continue;
        };
        minute.n += 1;
        if let Some(hr) = sample.hr.filter(|&h| h > 0) {
            minute.hr_sum += f64::from(hr);
            minute.hr_n += 1;
        }
        if sample.is_ambulatory() {
            minute.walk_s += 1;
        }
        if sample.is_asleep() || in_sleep(sample.ts, sleep) {
            minute.asleep_s += 1;
        }
    }
    out
}

struct Candidate {
    start: DateTime<Utc>,
    last: DateTime<Utc>,
    exerting_min: i64,
}

fn candidates(minutes: &[Minute], threshold_hr: f64, params: &WorkoutParams) -> Vec<Candidate> {
    let gap = Duration::minutes(params.rest_gap_min);
    let mut out = Vec::new();
    let mut open: Option<Candidate> = None;
    for minute in minutes {
        if !minute.exerting(threshold_hr, params) {
            continue;
        }
        match open.as_mut() {
            Some(c) if minute.start - c.last <= gap => {
                c.last = minute.start;
                c.exerting_min += 1;
            }
            _ => {
                out.extend(open.take());
                open = Some(Candidate {
                    start: minute.start,
                    last: minute.start,
                    exerting_min: 1,
                });
            }
        }
    }
    out.extend(open);
    out
}

fn summarise(
    samples: &[ActivitySample],
    increments: &[i64],
    candidate: &Candidate,
    physiology: &Physiology,
    params: &WorkoutParams,
) -> Option<Workout> {
    let start = candidate.start;
    let end = candidate.last + Duration::minutes(1);
    let duration_min = (end - start).num_minutes();
    let exerting_fraction = candidate.exerting_min as f64 / (duration_min as f64);
    if exerting_fraction < params.min_exerting_fraction {
        return None;
    }
    let from = samples.partition_point(|s| s.ts < start);
    let to = samples.partition_point(|s| s.ts < end);
    let window = &samples[from..to];
    if window.is_empty() {
        return None;
    }
    let walking = window.iter().filter(|s| s.is_ambulatory()).count();
    let walk_fraction = walking as f64 / window.len() as f64;
    let kind =
        if walk_fraction >= params.walk_session_fraction && duration_min >= params.min_walk_min {
            WorkoutKind::Walk
        } else if duration_min >= params.min_session_min {
            if walk_fraction <= params.resistance_walk_fraction {
                WorkoutKind::Resistance
            } else {
                WorkoutKind::Activity
            }
        } else {
            return None;
        };

    let hrs: Vec<f64> = window
        .iter()
        .filter_map(|s| s.hr.filter(|&h| h > 0))
        .map(f64::from)
        .collect();
    if hrs.is_empty() {
        return None;
    }
    let mut zones = ZoneSeconds::default();
    for &hr in &hrs {
        zones.add(hr, physiology.hr_max);
    }
    let trimp = zones.trimp();
    Some(Workout {
        start,
        end,
        kind,
        duration_s: (end - start).num_seconds(),
        avg_hr: hrs.iter().sum::<f64>() / hrs.len() as f64,
        max_hr: hrs.iter().fold(0.0_f64, |a, &b| a.max(b)) as u8,
        zones,
        trimp,
        load: load(trimp),
        kcal: physiology
            .body
            .map(|body| kcal_over_seconds(&body, hrs.iter().copied())),
        steps: steps_between(samples, increments, start, end),
        walk_fraction,
    })
}

/// Sessions in time order. `samples` must be sorted by time, one per second;
/// `sleep` lists detected sleep windows to exclude.
pub fn detect_workouts(
    samples: &[ActivitySample],
    sleep: &[(DateTime<Utc>, DateTime<Utc>)],
    physiology: &Physiology,
    params: &WorkoutParams,
) -> Vec<Workout> {
    let threshold = hr_reserve_threshold(
        physiology.resting_hr,
        physiology.hr_max,
        params.exert_hrr_fraction,
    );
    let minutes = minutes(samples, sleep);
    let increments = step_increments(samples);
    candidates(&minutes, threshold, params)
        .iter()
        .filter_map(|c| summarise(samples, &increments, c, physiology, params))
        .collect()
}

/// Zones, training impulse and load over every awake second with a heart rate.
pub fn day_load(
    samples: &[ActivitySample],
    sleep: &[(DateTime<Utc>, DateTime<Utc>)],
    physiology: &Physiology,
) -> DayLoad {
    let mut zones = ZoneSeconds::default();
    let mut awake_s = 0;
    for sample in samples {
        if sample.is_asleep() || in_sleep(sample.ts, sleep) {
            continue;
        }
        let Some(hr) = sample.hr.filter(|&h| h > 0) else {
            continue;
        };
        awake_s += 1;
        zones.add(f64::from(hr), physiology.hr_max);
    }
    let trimp = zones.trimp();
    DayLoad {
        zones,
        trimp,
        load: load(trimp),
        awake_s,
    }
}

#[cfg(test)]
mod tests;
