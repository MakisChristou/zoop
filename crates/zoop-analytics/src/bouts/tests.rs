use chrono::{TimeZone, Utc};

use super::*;

/// A scripted second-by-second recording: each segment is (seconds, walking, steps
/// per minute). The counter accumulates fractional steps like the strap's integer
/// counter would.
pub(crate) fn script(segments: &[(i64, bool, f64)]) -> Vec<ActivitySample> {
    let start = Utc.with_ymd_and_hms(2026, 10, 30, 9, 0, 0).unwrap();
    let mut samples = Vec::new();
    let mut steps = 0.0_f64;
    let mut t = 0_i64;
    for &(seconds, walking, cadence) in segments {
        for _ in 0..seconds {
            steps += cadence / 60.0;
            samples.push(ActivitySample {
                ts: start + Duration::seconds(t),
                hr: Some(90),
                steps: Some(steps.floor() as i32),
                activity: Some(if walking { 1 } else { 0 }),
                motion_g: None,
                band_state: 0,
            });
            t += 1;
        }
    }
    samples
}

#[test]
fn one_walk_with_a_short_pause_is_one_bout() {
    let samples = script(&[(600, true, 100.0), (90, false, 0.0), (600, true, 100.0)]);
    let bouts = detect_bouts(&samples);
    assert_eq!(bouts.len(), 1);
    let b = &bouts[0];
    assert_eq!(b.duration_s, 1290);
    assert!((b.steps - 2000).abs() <= 2, "steps {}", b.steps);
    assert!(
        (b.cadence_spm() - 93.0).abs() < 2.0,
        "cadence {}",
        b.cadence_spm()
    );
}

#[test]
fn a_long_pause_splits_bouts_and_steps_in_the_pause_are_not_counted() {
    let samples = script(&[(240, true, 100.0), (200, false, 20.0), (240, true, 110.0)]);
    let bouts = detect_bouts(&samples);
    assert_eq!(bouts.len(), 2);
    assert!((bouts[0].steps - 400).abs() <= 2, "{}", bouts[0].steps);
    assert!((bouts[1].steps - 440).abs() <= 2, "{}", bouts[1].steps);
    assert_eq!(bouts[0].end, bouts[0].start + Duration::seconds(240));
    assert_eq!(bouts[1].start, bouts[0].start + Duration::seconds(440));
}

#[test]
fn sporadic_walking_is_not_a_bout() {
    let samples = script(&[(60, false, 0.0), (100, true, 90.0), (300, false, 0.0)]);
    assert!(detect_bouts(&samples).is_empty());
}

#[test]
fn counter_resets_do_not_produce_negative_or_giant_steps() {
    let mut samples = script(&[(300, true, 100.0)]);
    for s in &mut samples[150..] {
        s.steps = s.steps.map(|v| v - 240);
    }
    let incs = step_increments(&samples);
    assert!(incs.iter().all(|&i| (0..=10).contains(&i)));
    let bouts = detect_bouts(&samples);
    assert_eq!(bouts.len(), 1);
    assert!((bouts[0].steps - 498).abs() <= 3, "{}", bouts[0].steps);
}

#[test]
fn steps_between_uses_half_open_range() {
    let samples = script(&[(120, true, 60.0)]);
    let incs = step_increments(&samples);
    let start = samples[0].ts;
    let first_minute = steps_between(&samples, &incs, start, start + Duration::seconds(60));
    let all = steps_between(&samples, &incs, start, start + Duration::seconds(600));
    assert!((first_minute - 59).abs() <= 1, "{first_minute}");
    assert!((all - 119).abs() <= 1, "{all}");
    assert_eq!(
        steps_between(
            &samples,
            &incs,
            start + Duration::seconds(600),
            start + Duration::seconds(700)
        ),
        0
    );
}
