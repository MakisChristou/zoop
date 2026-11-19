//! Walking bouts from one-second samples.
//!
//! The strap's own per-second activity label marks ambulatory seconds (walk or run);
//! steps come from positive increments of its counter, which resets whenever the strap
//! is removed or charged. Bouts follow the accelerometer convention of Troiano et al.
//! (2008), "Physical activity in the United States measured by accelerometer", Med
//! Sci Sports Exerc 40(1): 181–188: consecutive activity with interruptions of up to
//! two minutes tolerated. Cadence is reported in steps per minute so bouts can be read
//! against the bands of Tudor-Locke & Rowe (2012), "Using cadence to study free-living
//! ambulatory behaviour", Sports Med 42(5): 381–398, where 100 steps/min marks brisk
//! walking.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

/// One second of strap data as the activity analytics need it.
#[derive(Debug, Clone, PartialEq)]
pub struct ActivitySample {
    pub ts: DateTime<Utc>,
    pub hr: Option<u8>,
    /// The strap's cumulative step counter.
    pub steps: Option<i32>,
    /// The strap's own label: 0 still, 1 walk, 2 run; `None` when it had no opinion.
    pub activity: Option<u8>,
    /// Dynamic acceleration in g, when the record carried one.
    pub motion_g: Option<f32>,
    /// 0 wake, 1 still, 2 sleep, 3 up.
    pub band_state: u8,
}

impl ActivitySample {
    pub const ACTIVITY_WALK: u8 = 1;
    pub const ACTIVITY_RUN: u8 = 2;
    pub const BAND_SLEEP: u8 = 2;

    /// Whether the strap labelled this second as walking or running.
    pub fn is_ambulatory(&self) -> bool {
        matches!(
            self.activity,
            Some(Self::ACTIVITY_WALK) | Some(Self::ACTIVITY_RUN)
        )
    }

    /// Whether the strap flagged this second as sleep.
    pub fn is_asleep(&self) -> bool {
        self.band_state == Self::BAND_SLEEP
    }
}

/// Counter increments above this per second are resets or glitches, not steps.
pub const MAX_STEP_INCREMENT_PER_S: i32 = 10;
/// Interruptions up to this long stay inside a bout (Troiano 2008).
pub const BOUT_GAP_S: i64 = 120;
/// Shorter runs of walking are incidental movement, not a bout.
pub const MIN_BOUT_S: i64 = 180;

const SECONDS_PER_MINUTE: f64 = 60.0;

/// A run of walking with its step count.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Bout {
    pub start: DateTime<Utc>,
    /// Exclusive: one second after the last ambulatory sample.
    pub end: DateTime<Utc>,
    pub steps: i64,
    pub duration_s: i64,
}

impl Bout {
    /// Mean steps per minute over the bout.
    pub fn cadence_spm(&self) -> f64 {
        if self.duration_s <= 0 {
            return 0.0;
        }
        self.steps as f64 / (self.duration_s as f64 / SECONDS_PER_MINUTE)
    }
}

/// Steps attributed to each sample: the counter's increment since the previous
/// sample when it is a plausible number of steps, otherwise zero.
pub fn step_increments(samples: &[ActivitySample]) -> Vec<i64> {
    let mut previous: Option<i32> = None;
    samples
        .iter()
        .map(|sample| {
            let inc = match (previous, sample.steps) {
                (Some(prev), Some(now)) => {
                    let delta = now - prev;
                    if (0..=MAX_STEP_INCREMENT_PER_S).contains(&delta) {
                        i64::from(delta)
                    } else {
                        0
                    }
                }
                _ => 0,
            };
            if sample.steps.is_some() {
                previous = sample.steps;
            }
            inc
        })
        .collect()
}

/// Steps between `start` (inclusive) and `end` (exclusive), given the increments
/// from [`step_increments`] for the same samples.
pub fn steps_between(
    samples: &[ActivitySample],
    increments: &[i64],
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> i64 {
    let from = samples.partition_point(|s| s.ts < start);
    let to = samples.partition_point(|s| s.ts < end);
    increments[from..to].iter().sum()
}

struct OpenBout {
    start: DateTime<Utc>,
    last: DateTime<Utc>,
    steps_before: i64,
    steps_at_last: i64,
}

impl OpenBout {
    fn close(self) -> Option<Bout> {
        let duration_s = (self.last - self.start).num_seconds() + 1;
        (duration_s >= MIN_BOUT_S).then(|| Bout {
            start: self.start,
            end: self.last + Duration::seconds(1),
            steps: self.steps_at_last - self.steps_before,
            duration_s,
        })
    }
}

/// Walking bouts in time order. `samples` must be sorted by time.
pub fn detect_bouts(samples: &[ActivitySample]) -> Vec<Bout> {
    let increments = step_increments(samples);
    let mut bouts = Vec::new();
    let mut open: Option<OpenBout> = None;
    let mut cumulative = 0_i64;
    for (sample, inc) in samples.iter().zip(increments) {
        cumulative += inc;
        if !sample.is_ambulatory() {
            continue;
        }
        match open.as_mut() {
            Some(bout) if (sample.ts - bout.last).num_seconds() <= BOUT_GAP_S => {
                bout.last = sample.ts;
                bout.steps_at_last = cumulative;
            }
            _ => {
                bouts.extend(open.take().and_then(OpenBout::close));
                open = Some(OpenBout {
                    start: sample.ts,
                    last: sample.ts,
                    steps_before: cumulative - inc,
                    steps_at_last: cumulative,
                });
            }
        }
    }
    bouts.extend(open.and_then(OpenBout::close));
    bouts
}

#[cfg(test)]
mod tests;
