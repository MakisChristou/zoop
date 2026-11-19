use chrono::{TimeZone, Utc};

use super::*;
use crate::sleep::{SleepParams, detect_sleep};

/// A synthetic night with scripted physiology per phase so the classifier has
/// something to find: a deep block early, a REM block later, a wake block in between.
fn scripted_night() -> Vec<Sample> {
    let start = Utc.with_ymd_and_hms(2026, 10, 23, 23, 0, 0).unwrap();
    let total = 7 * 3600;
    (0..total)
        .map(|i| {
            let minute = i / 60;
            // phases by minute: 0-30 light, 30-90 deep, 90-100 wake, 100-240 light, 240-290 rem, 290-420 light
            let (hr, rr_var, resp_jitter, motion, awake) = match minute {
                30..=89 => (48u32, 30, 0.0, 0.004, false),
                90..=99 => (70, 12, 0.5, 0.2, true),
                240..=289 => (62, 10, 0.9, 0.005, false),
                _ => (55, 12, 0.3, 0.006, false),
            };
            let t = i as f64;
            let breath =
                (2.0 * std::f64::consts::PI * (14.0 + resp_jitter * ((t / 60.0).sin() * 3.0))
                    / 60.0
                    * t)
                    .sin();
            let rr = (60_000.0 / hr as f64 + rr_var as f64 * breath + ((i * 7919) % 11) as f64
                - 5.0) as u32;
            Sample {
                ts: start + Duration::seconds(i),
                hr: Some(hr as u8),
                rr_ms: vec![rr],
                motion_g: Some(motion + if i % 97 == 0 { 0.05 } else { 0.0 }),
                gravity_g: Some([0.1, 0.2, 0.97]),
                skin_temp_c: Some(34.0),
                band_state: if awake { 0 } else { Sample::BAND_SLEEP },
                spo2_pct: None,
            }
        })
        .collect()
}

#[test]
fn stages_tile_the_window_and_find_the_scripted_blocks() {
    let samples = scripted_night();
    let window = &detect_sleep(&samples, &SleepParams::default())[0];
    let (segments, summary) = stage_window(&samples, window);

    assert!(!segments.is_empty());
    assert_eq!(segments[0].start, window.onset);
    for pair in segments.windows(2) {
        assert_eq!(pair[0].end, pair[1].start, "segments are contiguous");
    }
    let total = summary.wake_s + summary.light_s + summary.deep_s + summary.rem_s;
    assert_eq!(total, summary.epochs as i64 * EPOCH_S);

    let minutes = |stage: Stage| {
        segments
            .iter()
            .filter(|s| s.stage == stage)
            .map(|s| (s.end - s.start).num_seconds())
            .sum::<i64>()
            / 60
    };
    assert!(
        minutes(Stage::Wake) >= 8,
        "wake block found: {} min",
        minutes(Stage::Wake)
    );
    assert!(
        minutes(Stage::Deep) >= 30,
        "deep block found: {} min",
        minutes(Stage::Deep)
    );
    assert!(
        minutes(Stage::Rem) >= 20,
        "rem block found: {} min",
        minutes(Stage::Rem)
    );
    assert!(summary.rem_latency_s.unwrap() >= NO_REM_AFTER_ONSET_S);
}

#[test]
fn no_data_means_no_stages() {
    let window = SleepWindow {
        onset: Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap(),
        offset: Utc.with_ymd_and_hms(2026, 1, 1, 1, 0, 0).unwrap(),
        time_in_bed_s: 3600,
        asleep_s: 3600,
        waso_s: 0,
        efficiency: 1.0,
        coverage_s: 0,
        disturbances: 0,
    };
    let (segments, summary) = stage_window(&[], &window);
    assert!(segments.is_empty());
    assert_eq!(summary.epochs, 0);
}

#[test]
fn posture_angle_is_ninety_degrees_when_z_points_up() {
    assert!((posture_angle_deg([0.0, 0.0, 1.0]) - 90.0).abs() < 1e-9);
    assert!(posture_angle_deg([1.0, 0.0, 0.0]).abs() < 1e-9);
}
