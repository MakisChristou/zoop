use super::*;
use chrono::Duration;
fn night(day: NaiveDate) -> Night {
    let read = |v| Reading {
        value: Some(v),
        quality: "good",
    };
    Night {
        day,
        id: 1,
        revision: 1,
        state: "ready",
        sleep: read(28800.0),
        hrv: read(50.0),
        resting_hr: read(55.0),
        onset_minute: 0.0,
        wake_minute: 480.0,
        timezone: "UTC".into(),
    }
}
fn fixture() -> (NaiveDate, Vec<Night>) {
    let day = NaiveDate::from_ymd_opt(2026, 3, 30).unwrap();
    (
        day,
        (0..=28)
            .map(|age| night(day - Duration::days(age)))
            .collect(),
    )
}
fn result(day: NaiveDate, nights: &[Night]) -> Recovery {
    calculate(day, "UTC", nights, false)
}
#[test]
fn frozen_candidate_v03_anchor_cases() {
    let (day, mut n) = fixture();
    assert_eq!(result(day, &n).score, Some(75));
    n[0].hrv.value = Some(52.5);
    n[0].resting_hr.value = Some(54.0);
    for (hours, expected) in [(3.0, 14), (6.5, 66), (8.0, 90), (10.0, 90)] {
        n[0].sleep.value = Some(hours * 3600.0);
        assert_eq!(result(day, &n).score, Some(expected));
    }
    n[0].hrv.value = Some(50.0);
    n[0].resting_hr.value = Some(55.0);
    n[0].sleep.value = Some(28800.0);
    for row in &mut n[1..7] {
        row.sleep.value = Some(21600.0);
    }
    assert_eq!(result(day, &n).score, Some(62));
}
#[test]
fn missing_pending_incomplete_and_extreme_signals_abstain() {
    for change in 0..9 {
        let (day, mut n) = fixture();
        match change {
            0 => n[0].hrv.value = None,
            1 => n[0].resting_hr.value = Some(f64::NAN),
            2 => n[0].sleep.value = Some(86401.0),
            3 => n[0].hrv.quality = "limited",
            4 => n[0].state = "updating",
            5 => n[0].state = "awaiting_sync",
            6 => n[0].hrv.value = Some(60.0),
            7 => n[0].resting_hr.value = Some(52.0),
            _ => n[0].timezone = "Europe/London".into(),
        }
        assert!(result(day, &n).score.is_none(), "case {change}");
    }
    let (day, n) = fixture();
    assert_eq!(calculate(day, "UTC", &n, true).state, "updating");
}
#[test]
fn bounds_conflict_and_half_up_rounding() {
    let (day, mut n) = fixture();
    n[0].hrv.value = Some(50.0 / 1.05_f64.powf(1.1));
    n[0].resting_hr.value = Some(53.9);
    let r = result(day, &n);
    assert_eq!(r.score, Some(59));
    assert!(r.conflict);
    n[0].hrv.value = Some(1.0);
    assert_eq!(result(day, &n).score, Some(0));
    n[0].hrv.value = Some(50.0 * 1.05_f64.powf(1.8));
    n[0].resting_hr.value = Some(53.2);
    assert_eq!(result(day, &n).score, Some(100));
    n[0].sleep.value = Some(28800.0 * (33.5_f64 / 100.0).sqrt());
    assert_eq!(result(day, &n).score, Some(34));
}
#[test]
fn dates_duplicates_and_saved_timezone_are_scoped_before_quality() {
    let (day, n) = fixture();
    let expected = result(day, &n).score;
    for offset in [-1, 29, 400] {
        let mut rows = n.clone();
        let mut bad = night(day - Duration::days(offset));
        bad.hrv.value = Some(99999.0);
        rows.push(bad);
        assert_eq!(result(day, &rows).score, expected);
    }
    for state in ["ready", "updating", "awaiting_sync"] {
        let mut rows = n.clone();
        let mut duplicate = n[1].clone();
        duplicate.state = state;
        duplicate.hrv.quality = "limited";
        rows.push(duplicate);
        assert_eq!(result(day, &rows).state, "ambiguous_history");
    }
    let mut rows = n.clone();
    let mut other = n[1].clone();
    other.timezone = "Asia/Tokyo".into();
    rows.push(other);
    assert_eq!(result(day, &rows).score, expected);
    rows.push(n[0].clone());
    assert_eq!(result(day, &rows).state, "ambiguous_history");
}
#[test]
fn paired_history_recent_gate_and_calendar_dst_window() {
    let (day, n) = fixture();
    let r = result(day, &n[..14]);
    assert_eq!(r.state, "learning");
    assert_eq!(r.baseline_count, 13);
    let mut rows = n.clone();
    for row in &mut rows[1..6] {
        row.sleep.quality = "limited";
    }
    let r = result(day, &rows);
    assert_eq!(r.state, "insufficient_recent_data");
    assert_eq!(r.recent_count, 2);
    let mut rows = n.clone();
    for row in &mut rows[1..16] {
        row.resting_hr.quality = "limited";
    }
    assert_eq!(result(day, &rows).state, "learning");
    // Local dates span Europe's spring DST change without elapsed-hour windows.
    let mut rows = n;
    for row in &mut rows {
        row.timezone = "Europe/London".into();
    }
    assert_eq!(
        calculate(day, "Europe/London", &rows, false).baseline_count,
        28
    );
}
// Frozen Python research v0.3 parity vectors; see docs/recovery.md.
#[test]
fn frozen_python_v03_parity_vectors() {
    let (day, _) = fixture();
    let cases = [
        (0, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (1, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (2, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (
            3,
            "ready",
            Some(25),
            [
                24.632457739903288,
                96.61730076368676,
                47.265625,
                70.44005102040816,
            ],
        ),
        (
            4,
            "ready",
            Some(30),
            [
                30.232712426363058,
                85.80865038184338,
                56.25,
                71.9467474489796,
            ],
        ),
        (
            5,
            "ready",
            Some(36),
            [35.666598075004515, 75.0, 66.015625, 73.46938775510203],
        ),
        (
            6,
            "ready",
            Some(41),
            [
                40.943714957176226,
                64.19134961815662,
                76.5625,
                75.00797193877553,
            ],
        ),
        (
            7,
            "ready",
            Some(46),
            [46.072855623606394, 53.382699236313236, 87.890625, 76.5625],
        ),
        (
            8,
            "ready",
            Some(43),
            [
                51.06209304831589,
                42.57404885446986,
                100.0,
                78.13297193877551,
            ],
        ),
        (
            9,
            "ready",
            Some(25),
            [55.91885706758503, 31.765398472626472, 25.0, 66.015625],
        ),
        (
            10,
            "ready",
            Some(21),
            [
                60.65000093102881,
                20.956748090783094,
                31.640625,
                67.47448979591836,
            ],
        ),
        (11, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (12, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (13, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (
            14,
            "ready",
            Some(66),
            [
                78.43832400235955,
                96.61730076368676,
                66.015625,
                73.46938775510203,
            ],
        ),
        (
            15,
            "ready",
            Some(75),
            [
                82.62768341628286,
                85.80865038184338,
                76.5625,
                75.00797193877553,
            ],
        ),
        (
            16,
            "ready",
            Some(75),
            [86.72324327582648, 75.0, 87.890625, 76.5625],
        ),
        (
            17,
            "ready",
            Some(64),
            [
                90.72911209438884,
                64.19134961815662,
                100.0,
                78.13297193877551,
            ],
        ),
        (
            18,
            "ready",
            Some(25),
            [94.64913422485043, 53.382699236313236, 25.0, 66.015625],
        ),
        (
            19,
            "ready",
            Some(32),
            [
                98.48691203113762,
                42.57404885446986,
                31.640625,
                67.47448979591836,
            ],
        ),
        (
            20,
            "ready",
            Some(32),
            [100.0, 31.765398472626472, 39.0625, 68.94929846938777],
        ),
        (21, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (22, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (23, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (24, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (25, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (26, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (27, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (28, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (29, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (30, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (31, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (32, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (33, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (34, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (35, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (36, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (37, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (38, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
        (39, "unusual_signals", None, [0.0, 0.0, 0.0, 0.0]),
    ];
    for (case, state, score, components) in cases {
        let mut n = (0..=28)
            .map(|age| {
                let mut n = night(day - Duration::days(age));
                n.hrv.value = Some(45.0 + (age % 5) as f64 * 3.0);
                n.resting_hr.value = Some(53.0 + (age % 5) as f64);
                n.sleep.value = Some((6.0 + (age % 5) as f64 / 2.0) * 3600.0);
                n
            })
            .collect::<Vec<_>>();
        n[0].hrv.value = Some(35.0 + f64::from(case) * 1.2);
        n[0].resting_hr.value = Some(50.0 + f64::from(case % 11));
        n[0].sleep.value = Some((4.0 + f64::from(case % 9) / 2.0) * 3600.0);
        let r = result(day, &n);
        assert_eq!(r.state, state, "case {case}");
        assert_eq!(r.score, score, "case {case}");
        if let Some(c) = r.components {
            for (actual, expected) in [c.hrv, c.resting_hr, c.last_sleep, c.recent_sleep]
                .into_iter()
                .zip(components)
            {
                assert!(
                    (actual - expected).abs() < 1e-9,
                    "case {case}: {actual} != {expected}"
                );
            }
        }
    }
}

#[test]
fn half_up_boundary_is_stable_across_float_implementations() {
    for value in [58.5, 58.49999999999999, 58.50000000000001] {
        assert_eq!(rounded_score(value), 59);
    }
    assert_eq!(rounded_score(58.5 - 2e-9), 58);
    assert_eq!(rounded_score(58.5 + 2e-9), 59);
}
