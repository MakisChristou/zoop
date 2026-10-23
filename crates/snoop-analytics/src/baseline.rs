//! Rolling personal baselines: winsorised exponentially weighted mean and variance,
//! so one bad night cannot drag a 30-day baseline.

#[cfg(test)]
mod tests;

/// Observations beyond this many standard deviations are clamped before updating.
const WINSOR_SIGMA: f64 = 3.0;
/// Minimum observations before a z-score is meaningful.
const MIN_OBSERVATIONS: u32 = 3;

#[derive(Debug, Clone, Copy, Default, serde::Serialize, serde::Deserialize)]
pub struct Baseline {
    pub mean: f64,
    pub variance: f64,
    pub count: u32,
}

impl Baseline {
    /// `alpha` ≈ 2 / (N + 1); N = 7 for a weekly baseline, 30 for monthly.
    pub fn update(&mut self, observation: f64, alpha: f64) {
        if self.count == 0 {
            *self = Self {
                mean: observation,
                variance: 0.0,
                count: 1,
            };
            return;
        }
        let sd = self.variance.sqrt();
        let clamped = if sd > 0.0 {
            observation.clamp(self.mean - WINSOR_SIGMA * sd, self.mean + WINSOR_SIGMA * sd)
        } else {
            observation
        };
        let diff = clamped - self.mean;
        self.mean += alpha * diff;
        self.variance = (1.0 - alpha) * (self.variance + alpha * diff * diff);
        self.count += 1;
    }

    /// Standard score of a new observation against this baseline.
    pub fn z_score(&self, observation: f64) -> Option<f64> {
        let sd = self.variance.sqrt();
        (self.count >= MIN_OBSERVATIONS && sd > 0.0).then(|| (observation - self.mean) / sd)
    }
}
