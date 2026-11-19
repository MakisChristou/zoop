//! Heart-rate zones, training impulse and the 0–21 load display scale.
//!
//! Zones and the training impulse follow Edwards (1993), *The Heart Rate Monitor
//! Book*, Fleet Feet Press: five bands at 50–60, 60–70, 70–80, 80–90 and 90–100 % of
//! maximal heart rate, and a summated impulse equal to the minutes in each band
//! weighted 1 to 5. Maximal heart rate is predicted from age with Tanaka, Monahan &
//! Seals (2001), "Age-predicted maximal heart rate revisited", J Am Coll Cardiol
//! 37(1): 153–156 (HRmax = 208 − 0.7 · age) and replaced by a higher value when the
//! strap has recorded one. Heart-rate reserve follows Karvonen, Kentala & Mustala
//! (1957), "The effects of training on heart rate", Ann Med Exp Biol Fenn 35: 307–315.
//!
//! [`load`] maps the impulse onto a 0–21 display scale through a saturating curve so
//! that a brisk walk reads around 6 and a hard hour-long session around 15. The scale
//! is a presentation choice, not a measurement, and reproduces no proprietary formula.

use serde::{Deserialize, Serialize};

/// Number of Edwards zones.
pub const ZONES: usize = 5;
/// Lower bound of each zone as a fraction of maximal heart rate.
pub const ZONE_LOWER_FRACTION: [f64; ZONES] = [0.5, 0.6, 0.7, 0.8, 0.9];
/// Top of the display scale.
pub const LOAD_MAX: f64 = 21.0;
/// Training impulse at which the display scale reaches 1 − 1/e of its maximum.
pub const LOAD_SCALE: f64 = 150.0;

const ZONE_WEIGHT: [f64; ZONES] = [1.0, 2.0, 3.0, 4.0, 5.0];
const TANAKA_INTERCEPT: f64 = 208.0;
const TANAKA_SLOPE: f64 = 0.7;
const SECONDS_PER_MINUTE: f64 = 60.0;

/// Seconds spent in each zone, lowest first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ZoneSeconds(pub [u32; ZONES]);

impl ZoneSeconds {
    /// Counts one second at `hr`. Below the first zone nothing is counted.
    pub fn add(&mut self, hr: f64, hr_max: f64) {
        if let Some(zone) = zone_of(hr, hr_max) {
            self.0[zone] += 1;
        }
    }

    /// Adds another tally to this one.
    pub fn merge(&mut self, other: &Self) {
        for (mine, theirs) in self.0.iter_mut().zip(other.0) {
            *mine += theirs;
        }
    }

    /// Whole minutes per zone, rounded to nearest.
    pub fn minutes(&self) -> [i32; ZONES] {
        let mut out = [0; ZONES];
        for (minutes, seconds) in out.iter_mut().zip(self.0) {
            *minutes = (f64::from(seconds) / SECONDS_PER_MINUTE).round() as i32;
        }
        out
    }

    /// Total seconds in any zone.
    pub fn total(&self) -> u32 {
        self.0.iter().sum()
    }

    /// Edwards summated-zone training impulse: minutes in each zone times its weight.
    pub fn trimp(&self) -> f64 {
        self.0
            .iter()
            .zip(ZONE_WEIGHT)
            .map(|(&seconds, weight)| f64::from(seconds) / SECONDS_PER_MINUTE * weight)
            .sum()
    }
}

/// Tanaka (2001) age-predicted maximal heart rate.
pub fn predicted_hr_max(age_years: f64) -> f64 {
    TANAKA_SLOPE.mul_add(-age_years, TANAKA_INTERCEPT)
}

/// Maximal heart rate to cut zones with: the age prediction when the age is known,
/// raised to the observed maximum when the strap has seen a higher sustained value.
/// `None` only when neither is available.
pub fn hr_max(age_years: Option<f64>, observed_max: Option<f64>) -> Option<f64> {
    match (age_years.map(predicted_hr_max), observed_max) {
        (Some(predicted), Some(observed)) => Some(predicted.max(observed)),
        (Some(predicted), None) => Some(predicted),
        (None, Some(observed)) => Some(observed),
        (None, None) => None,
    }
}

/// Zone index (0–4) for a heart rate, or `None` below 50 % of maximum.
pub fn zone_of(hr: f64, hr_max: f64) -> Option<usize> {
    if hr_max <= 0.0 {
        return None;
    }
    let fraction = hr / hr_max;
    ZONE_LOWER_FRACTION
        .iter()
        .rposition(|&lower| fraction >= lower)
}

/// Heart rate at a fraction of heart-rate reserve (Karvonen).
pub fn hr_reserve_threshold(resting_hr: f64, hr_max: f64, fraction: f64) -> f64 {
    fraction.mul_add(hr_max - resting_hr, resting_hr)
}

/// Display load on a 0–21 scale: `LOAD_MAX · (1 − e^(−trimp / LOAD_SCALE))`.
pub fn load(trimp: f64) -> f64 {
    if trimp <= 0.0 {
        return 0.0;
    }
    LOAD_MAX * (1.0 - (-trimp / LOAD_SCALE).exp())
}

#[cfg(test)]
mod tests;
