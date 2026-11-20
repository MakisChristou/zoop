//! Time-domain HRV from R-R intervals in milliseconds.
//!
//! Task Force of the ESC/NASPE (1996), "Heart rate variability: standards of
//! measurement, physiological interpretation and clinical use".

#[cfg(test)]
mod tests;

const RR_MIN_MS: f64 = 300.0;
const RR_MAX_MS: f64 = 2000.0;
/// Successive beats differing by more than this fraction are treated as ectopic.
const MAX_SUCCESSIVE_CHANGE: f64 = 0.20;

/// Drops physiologically impossible intervals and gross ectopic beats. Comparison
/// is against the last *accepted* beat so one artefact cannot poison the next.
pub fn clean_rr(rr_ms: &[u32]) -> Vec<f64> {
    let mut cleaned = Vec::with_capacity(rr_ms.len());
    let mut previous: Option<f64> = None;
    for &rr in rr_ms {
        let rr = f64::from(rr);
        if !(RR_MIN_MS..=RR_MAX_MS).contains(&rr) {
            continue;
        }
        if let Some(prev) = previous
            && ((rr - prev) / prev).abs() > MAX_SUCCESSIVE_CHANGE
        {
            continue;
        }
        cleaned.push(rr);
        previous = Some(rr);
    }
    cleaned
}

/// Root mean square of successive differences. `None` with fewer than 2 intervals.
pub fn rmssd(rr_ms: &[f64]) -> Option<f64> {
    if rr_ms.len() < 2 {
        return None;
    }
    let sum: f64 = rr_ms.windows(2).map(|w| (w[1] - w[0]).powi(2)).sum();
    Some((sum / (rr_ms.len() - 1) as f64).sqrt())
}

/// Standard deviation of NN intervals. `None` with fewer than 2 intervals.
pub fn sdnn(rr_ms: &[f64]) -> Option<f64> {
    if rr_ms.len() < 2 {
        return None;
    }
    let n = rr_ms.len() as f64;
    let mean = rr_ms.iter().sum::<f64>() / n;
    let variance = rr_ms.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / (n - 1.0);
    Some(variance.sqrt())
}

/// ln(RMSSD), the quantity most readiness scores are built on (Plews et al. 2013,
/// Int J Sports Physiol Perform).
pub fn ln_rmssd(rr_ms: &[f64]) -> Option<f64> {
    rmssd(rr_ms).filter(|value| *value > 0.0).map(f64::ln)
}
