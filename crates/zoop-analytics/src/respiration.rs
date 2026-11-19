//! Respiratory rate from respiratory sinus arrhythmia.
//!
//! Breathing modulates heart rate: the R-R series carries a component at the
//! breathing frequency. Over a window of beats the tachogram is resampled at 4 Hz,
//! detrended, and its power spectrum is read for the strongest peak in the
//! respiratory band (0.1–0.5 Hz, 6–30 breaths/min). A direct Fourier transform is
//! used so no FFT dependency is needed; windows are short.
//!
//! References: DeBoer, Karemaker & Strackee (1984); Task Force of ESC/NASPE (1996).

const RESAMPLE_HZ: f64 = 4.0;
const BAND_LOW_HZ: f64 = 0.10;
const BAND_HIGH_HZ: f64 = 0.50;
const MIN_BEATS: usize = 30;
const MIN_SECONDS: f64 = 40.0;
/// The chosen peak must carry at least this share of in-band power.
const MIN_PEAK_DOMINANCE: f64 = 0.15;

/// Breaths per minute from clean R-R intervals (ms) of roughly one minute.
pub fn rate_from_rr(rr_ms: &[f64]) -> Option<f64> {
    if rr_ms.len() < MIN_BEATS {
        return None;
    }
    // Beat times (s) and the tachogram value at each beat.
    let mut times = Vec::with_capacity(rr_ms.len());
    let mut t = 0.0;
    for &rr in rr_ms {
        t += rr / 1000.0;
        times.push(t);
    }
    let span = t;
    if span < MIN_SECONDS {
        return None;
    }

    // Linear resampling at 4 Hz.
    let n = (span * RESAMPLE_HZ) as usize;
    let mut series = Vec::with_capacity(n);
    let mut j = 0;
    for i in 0..n {
        let ti = i as f64 / RESAMPLE_HZ;
        while j + 1 < times.len() && times[j + 1] < ti {
            j += 1;
        }
        let value = if j + 1 < times.len() {
            let (t0, t1) = (times[j], times[j + 1]);
            let (v0, v1) = (rr_ms[j], rr_ms[j + 1]);
            if t1 > t0 {
                v0 + (v1 - v0) * (ti - t0) / (t1 - t0)
            } else {
                v0
            }
        } else {
            rr_ms[j]
        };
        series.push(value);
    }
    let mean = series.iter().sum::<f64>() / series.len() as f64;
    for v in &mut series {
        *v -= mean;
    }

    // Power spectrum over the respiratory band by direct DFT.
    let df = RESAMPLE_HZ / n as f64;
    let (mut best_f, mut best_p, mut total) = (0.0, 0.0, 0.0);
    let mut k = (BAND_LOW_HZ / df).ceil() as usize;
    while (k as f64) * df <= BAND_HIGH_HZ && k < n / 2 {
        let f = k as f64 * df;
        let (mut re, mut im) = (0.0, 0.0);
        for (i, v) in series.iter().enumerate() {
            let angle = -2.0 * std::f64::consts::PI * f * i as f64 / RESAMPLE_HZ;
            re += v * angle.cos();
            im += v * angle.sin();
        }
        let p = re * re + im * im;
        total += p;
        if p > best_p {
            best_p = p;
            best_f = f;
        }
        k += 1;
    }
    (total > 0.0 && best_p / total >= MIN_PEAK_DOMINANCE).then_some(best_f * 60.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn synthetic(breaths_per_min: f64, seconds: f64) -> Vec<f64> {
        // 60 bpm with ±40 ms sinusoidal RSA at the breathing frequency.
        let mut rr = Vec::new();
        let mut t = 0.0;
        while t < seconds {
            let modulation = 40.0 * (2.0 * std::f64::consts::PI * breaths_per_min / 60.0 * t).sin();
            let interval = 1000.0 + modulation;
            rr.push(interval);
            t += interval / 1000.0;
        }
        rr
    }

    #[test]
    fn recovers_synthetic_breathing_rates() {
        for target in [9.0, 14.0, 18.0] {
            let rate = rate_from_rr(&synthetic(target, 60.0)).unwrap();
            assert!((rate - target).abs() < 1.0, "target {target} got {rate}");
        }
    }

    #[test]
    fn too_little_data_yields_none() {
        assert_eq!(rate_from_rr(&synthetic(14.0, 20.0)), None);
        assert_eq!(rate_from_rr(&[]), None);
    }
}
