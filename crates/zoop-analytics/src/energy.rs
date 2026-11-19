//! Energy expenditure from heart rate.
//!
//! Keytel, Goedecke, Noakes, Hiiloskorpi, Laukkanen, van der Merwe & Lambert (2005),
//! "Prediction of energy expenditure from heart rate monitoring during submaximal
//! exercise", J Sports Sci 23(3): 289–297. The sex-specific equations without
//! VO₂max predict kJ/min from heart rate, body mass and age. They were fitted on
//! steady-state exercise, so values near resting heart rate are extrapolations:
//! negative predictions are clamped to zero and callers should only sum over
//! exercise. Kilojoules are converted to kilocalories.

use serde::{Deserialize, Serialize};

const KJ_PER_KCAL: f64 = 4.184;
const SECONDS_PER_MINUTE: f64 = 60.0;

/// Biological sex as used by the Keytel equations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Sex {
    Male,
    Female,
}

impl Sex {
    /// Parses the stored representation, `male` or `female`.
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "male" => Some(Self::Male),
            "female" => Some(Self::Female),
            _ => None,
        }
    }
}

/// The inputs the equations need.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Body {
    pub sex: Sex,
    pub age_years: f64,
    pub weight_kg: f64,
}

struct Coefficients {
    intercept: f64,
    hr: f64,
    weight: f64,
    age: f64,
}

const MALE: Coefficients = Coefficients {
    intercept: -55.0969,
    hr: 0.6309,
    weight: 0.1988,
    age: 0.2017,
};

const FEMALE: Coefficients = Coefficients {
    intercept: -20.4022,
    hr: 0.4472,
    weight: -0.1263,
    age: 0.074,
};

/// Predicted kilojoules per minute at `hr`, clamped at zero.
pub fn kj_per_minute(body: &Body, hr: f64) -> f64 {
    let c = match body.sex {
        Sex::Male => MALE,
        Sex::Female => FEMALE,
    };
    let kj = c.intercept + c.hr * hr + c.weight * body.weight_kg + c.age * body.age_years;
    kj.max(0.0)
}

/// Predicted kilocalories per minute at `hr`, clamped at zero.
pub fn kcal_per_minute(body: &Body, hr: f64) -> f64 {
    kj_per_minute(body, hr) / KJ_PER_KCAL
}

/// Kilocalories over one-second heart-rate samples.
pub fn kcal_over_seconds<I: IntoIterator<Item = f64>>(body: &Body, hrs: I) -> f64 {
    hrs.into_iter()
        .map(|hr| kcal_per_minute(body, hr) / SECONDS_PER_MINUTE)
        .sum()
}

#[cfg(test)]
mod tests;
