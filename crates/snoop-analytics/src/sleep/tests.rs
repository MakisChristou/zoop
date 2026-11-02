use chrono::{TimeZone, Utc};

use super::*;

fn night(asleep_from: i64, asleep_to: i64, total: i64, awake_gaps: &[(i64, i64)]) -> Vec<Sample> {
    let start = Utc.with_ymd_and_hms(2026, 10, 23, 20, 0, 0).unwrap();
    (0..total)
        .map(|i| {
            let asleep = i >= asleep_from
                && i < asleep_to
                && !awake_gaps.iter().any(|&(a, b)| i >= a && i < b);
            let hr = if asleep { 52 } else { 72 };
            Sample {
                ts: start + Duration::seconds(i),
                hr: Some(hr),
                rr_ms: if asleep {
                    vec![60_000 / u32::from(hr) + (i % 7) as u32 * 4]
                } else {
                    vec![]
                },
                motion_g: Some(if asleep { 0.01 } else { 0.3 }),
                gravity_g: Some([0.0, 0.0, 1.0]),
                skin_temp_c: Some(if asleep { 34.0 } else { 32.5 }),
                band_state: if asleep { Sample::BAND_SLEEP } else { 0 },
                spo2_pct: if asleep && i % 1200 < 30 {
                    Some(96)
                } else {
                    None
                },
            }
        })
        .collect()
}

#[test]
fn detects_one_night_and_keeps_short_awakenings_inside() {
    // 7 h asleep starting 4 h in, with a 5-minute awakening and a 40-second blip.
    let samples = night(
        4 * 3600,
        11 * 3600,
        14 * 3600,
        &[(7 * 3600, 7 * 3600 + 300), (9 * 3600, 9 * 3600 + 40)],
    );
    let windows = detect_sleep(&samples, &SleepParams::default());
    assert_eq!(windows.len(), 1);
    let w = &windows[0];
    assert!(
        (w.time_in_bed_s - 7 * 3600).abs() <= 300,
        "tib {}",
        w.time_in_bed_s
    );
    assert_eq!(w.waso_s, 340);
    assert_eq!(w.disturbances, 1, "only the 5-minute awakening counts");
    assert!(w.efficiency > 0.98);
}

#[test]
fn ignores_short_rests_and_elevated_hr() {
    // A 10-minute "sleep" flag in the afternoon is not a nap.
    let samples = night(2 * 3600, 2 * 3600 + 600, 4 * 3600, &[]);
    assert!(detect_sleep(&samples, &SleepParams::default()).is_empty());

    // Flagged asleep for 2 h but heart rate is higher than when awake: not confirmed.
    let mut samples = night(3600, 3 * 3600, 5 * 3600, &[]);
    for s in &mut samples {
        if s.band_state == Sample::BAND_SLEEP {
            s.hr = Some(85);
        }
    }
    assert!(detect_sleep(&samples, &SleepParams::default()).is_empty());
}

#[test]
fn night_metrics_are_computed_over_the_window() {
    let samples = night(3600, 8 * 3600, 10 * 3600, &[]);
    let w = &detect_sleep(&samples, &SleepParams::default())[0];
    let m = night_metrics(&samples, w);
    assert!((m.resting_hr.unwrap() - 52.0).abs() < 0.5);
    assert!(m.hrv_windows > 60);
    assert!(m.hrv_rmssd_ms.unwrap() > 0.0);
    assert!((m.skin_temp_c.unwrap() - 34.0).abs() < 0.01);
    assert_eq!(m.spo2_pct, Some(96.0));
    assert_eq!(m.spo2_windows, 21);
}

#[test]
fn empty_input_yields_nothing() {
    assert!(detect_sleep(&[], &SleepParams::default()).is_empty());
}

#[test]
fn a_return_to_sleep_after_32_minutes_stays_in_one_episode() {
    let wake_s = 32 * 60 + 30;
    let samples = night(3600, 9 * 3600, 10 * 3600, &[(6 * 3600, 6 * 3600 + wake_s)]);
    let windows = detect_sleep(&samples, &SleepParams::default());
    assert_eq!(windows.len(), 1);
    let window = &windows[0];
    assert_eq!(window.time_in_bed_s, 8 * 3600);
    assert_eq!(window.asleep_s, 8 * 3600 - wake_s);
    assert_eq!(
        window.waso_s, wake_s,
        "joining never reclassifies wake as sleep"
    );
    assert_eq!(window.disturbances, 1);
}

#[test]
fn a_longer_awake_interval_still_separates_sleep_episodes() {
    let samples = night(3600, 9 * 3600, 10 * 3600, &[(6 * 3600, 6 * 3600 + 50 * 60)]);
    let windows = detect_sleep(&samples, &SleepParams::default());
    assert_eq!(windows.len(), 2);
    assert!(windows[0].offset < windows[1].onset);
    assert_eq!(
        windows.iter().map(|w| w.asleep_s).sum::<i64>(),
        8 * 3600 - 50 * 60
    );
}

#[test]
fn joining_across_missing_readings_never_invents_sleep_or_awake_seconds() {
    let mut samples = night(3600, 9 * 3600, 10 * 3600, &[]);
    let first = samples[0].ts;
    let missing_s = 32 * 60 + 30;
    samples.retain(|s| {
        let second = (s.ts - first).num_seconds();
        !(6 * 3600..6 * 3600 + missing_s).contains(&second)
    });
    let windows = detect_sleep(&samples, &SleepParams::default());
    assert_eq!(windows.len(), 1);
    assert_eq!(windows[0].waso_s, 0);
    assert_eq!(windows[0].asleep_s, 8 * 3600 - missing_s);
    assert_eq!(windows[0].time_in_bed_s - windows[0].coverage_s, missing_s);
}
