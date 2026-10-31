use chrono::{TimeZone, Utc};

use super::*;
use crate::energy::Sex;

/// A scripted day: each segment is (minutes, heart rate, walking, asleep).
fn day(segments: &[(i64, u8, bool, bool)]) -> Vec<ActivitySample> {
    let start = Utc.with_ymd_and_hms(2026, 10, 30, 8, 0, 0).unwrap();
    let mut samples = Vec::new();
    let mut steps = 0.0_f64;
    let mut t = 0_i64;
    for &(minutes, hr, walking, asleep) in segments {
        for _ in 0..minutes * 60 {
            if walking {
                steps += 100.0 / 60.0;
            }
            samples.push(ActivitySample {
                ts: start + Duration::seconds(t),
                hr: Some(hr),
                steps: Some(steps.floor() as i32),
                activity: Some(if walking { 1 } else { 0 }),
                motion_g: None,
                band_state: if asleep { 2 } else { 0 },
            });
            t += 1;
        }
    }
    samples
}

fn physiology() -> Physiology {
    Physiology {
        hr_max: 190.0,
        resting_hr: 55.0,
        body: Some(Body {
            sex: Sex::Male,
            age_years: 30.0,
            weight_kg: 80.0,
        }),
    }
}

fn detect(samples: &[ActivitySample]) -> Vec<Workout> {
    detect_workouts(samples, &[], &physiology(), &WorkoutParams::default())
}

const REST: (i64, u8, bool, bool) = (30, 70, false, false);

#[test]
fn a_walk_becomes_a_walk_session_with_steps_and_load() {
    let samples = day(&[REST, (25, 100, true, false), REST]);
    let found = detect(&samples);
    assert_eq!(found.len(), 1);
    let w = &found[0];
    assert_eq!(w.kind, WorkoutKind::Walk);
    assert_eq!(w.duration_s, 25 * 60);
    assert_eq!(w.start, samples[30 * 60].ts);
    assert!((w.steps - 2500).abs() <= 2, "steps {}", w.steps);
    assert!((w.avg_hr - 100.0).abs() < 1e-9);
    assert_eq!(w.max_hr, 100);
    // 100 bpm is 52.6 % of 190: zone 1 for 25 minutes, TRIMP 25.
    assert_eq!(w.zones.0, [1500, 0, 0, 0, 0]);
    assert!((w.trimp - 25.0).abs() < 1e-9);
    assert!(w.load > 3.0 && w.load < 4.0, "load {}", w.load);
    // Keytel at 100 bpm for a 30-year-old 80 kg man is 7.2 kcal/min.
    assert!(
        w.kcal.is_some_and(|k| k > 170.0 && k < 190.0),
        "{:?}",
        w.kcal
    );
    assert!((w.walk_fraction - 1.0).abs() < 1e-9);
}

#[test]
fn a_gym_session_with_rests_between_sets_is_one_resistance_session() {
    let mut segments = vec![REST];
    for _ in 0..8 {
        segments.push((3, 140, false, false));
        segments.push((3, 95, false, false));
    }
    segments.push(REST);
    let samples = day(&segments);
    let found = detect(&samples);
    assert_eq!(found.len(), 1, "{found:?}");
    let w = &found[0];
    assert_eq!(w.kind, WorkoutKind::Resistance);
    // Starts at the first set, ends after the last set (the trailing rest is trimmed).
    assert_eq!(w.start, samples[30 * 60].ts);
    assert_eq!(w.duration_s, 45 * 60);
    assert_eq!(w.steps, 0);
    assert!(w.max_hr == 140);
    assert!(w.avg_hr > 110.0 && w.avg_hr < 125.0, "{}", w.avg_hr);
}

#[test]
fn a_four_minute_rest_stays_inside_but_a_twelve_minute_rest_splits() {
    let samples = day(&[
        REST,
        (15, 140, false, false),
        (4, 90, false, false),
        (15, 140, false, false),
        REST,
    ]);
    let found = detect(&samples);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].duration_s, 34 * 60);

    let samples = day(&[
        REST,
        (22, 140, false, false),
        (12, 90, false, false),
        (22, 140, false, false),
        REST,
    ]);
    let found = detect(&samples);
    assert_eq!(found.len(), 2);
    assert!(found.iter().all(|w| w.duration_s == 22 * 60));
    assert!(found.iter().all(|w| w.kind == WorkoutKind::Resistance));
}

#[test]
fn short_bursts_are_not_sessions() {
    let samples = day(&[
        REST,
        (7, 100, true, false),
        REST,
        (15, 140, false, false),
        REST,
    ]);
    assert!(detect(&samples).is_empty());
}

#[test]
fn sleep_never_exerts() {
    let samples = day(&[(60, 140, false, true), REST]);
    assert!(detect(&samples).is_empty());

    let awake = day(&[(60, 140, false, false), REST]);
    let onset = awake[0].ts;
    let offset = awake[60 * 60].ts;
    let found = detect_workouts(
        &awake,
        &[(onset, offset)],
        &physiology(),
        &WorkoutParams::default(),
    );
    assert!(found.is_empty());
    assert_eq!(detect(&awake).len(), 1);
}

#[test]
fn mixed_exertion_is_left_unlabelled() {
    let mut segments = vec![REST];
    for _ in 0..6 {
        segments.push((2, 130, true, false));
        segments.push((3, 130, false, false));
    }
    segments.push(REST);
    let samples = day(&segments);
    let found = detect(&samples);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].kind, WorkoutKind::Activity);
    assert!((found[0].walk_fraction - 0.4).abs() < 1e-9);
}

#[test]
fn scattered_spikes_do_not_chain_into_a_session() {
    let mut segments = vec![REST];
    for _ in 0..10 {
        segments.push((1, 140, false, false));
        segments.push((5, 70, false, false));
    }
    segments.push(REST);
    assert!(detect(&day(&segments)).is_empty());
}

#[test]
fn no_body_means_no_calories() {
    let samples = day(&[REST, (25, 100, true, false), REST]);
    let phys = Physiology {
        body: None,
        ..physiology()
    };
    let found = detect_workouts(&samples, &[], &phys, &WorkoutParams::default());
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].kcal, None);
}

#[test]
fn day_load_counts_awake_seconds_only() {
    let samples = day(&[
        (60, 60, false, true),
        REST,
        (10, 140, false, false),
        (10, 175, false, false),
    ]);
    let d = day_load(&samples, &[], &physiology());
    assert_eq!(d.awake_s, 50 * 60);
    // 140 is 73.7 % of 190 (zone 3), 175 is 92 % (zone 5); 70 is 36.8 % (none).
    assert_eq!(d.zones.0, [0, 0, 600, 0, 600]);
    assert!((d.trimp - 80.0).abs() < 1e-9);
    assert!((d.load - load(80.0)).abs() < 1e-9);
}

#[test]
fn kind_round_trips() {
    for kind in [
        WorkoutKind::Walk,
        WorkoutKind::Resistance,
        WorkoutKind::Activity,
    ] {
        assert_eq!(WorkoutKind::parse(kind.as_str()), Some(kind));
    }
    assert_eq!(WorkoutKind::parse("swim"), None);
}
