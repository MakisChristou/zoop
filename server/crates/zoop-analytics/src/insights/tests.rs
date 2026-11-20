use super::*;
fn day(n: i64) -> NaiveDate {
    NaiveDate::from_ymd_opt(2025, 1, 1).unwrap() + Duration::days(n)
}
fn night(n: i64) -> Night {
    Night {
        day: day(n),
        id: n,
        revision: 1,
        state: "ready",
        sleep: Reading {
            value: Some(28800.0),
            quality: "good",
        },
        hrv: Reading {
            value: Some(50.0 + n as f64),
            quality: "good",
        },
        resting_hr: Reading {
            value: Some(55.0),
            quality: "good",
        },
        onset_minute: 1430.0,
        wake_minute: 470.0,
        timezone: "UTC".into(),
    }
}
#[test]
fn learning_gates_and_exclusion_of_target_and_future() {
    for (count, state) in [
        (6, "learning"),
        (7, "early"),
        (13, "early"),
        (14, "established"),
    ] {
        let mut nights = (0..=count).map(night).collect::<Vec<_>>();
        nights.push(night(50));
        let result = calculate(day(count), "UTC", &nights, false);
        assert_eq!(result.metrics[0].baseline.count, count as usize);
        assert_eq!(result.metrics[0].baseline.state, state);
        assert_eq!(result.metrics[0].baseline.average.is_some(), count >= 7);
        assert_eq!(result.metrics[0].baseline.lower.is_some(), count >= 14);
        assert_eq!(result.metrics[0].relation.is_some(), count >= 14);
    }
}
#[test]
fn bounded_calendar_window_and_independent_quality() {
    let mut nights = (0..=40).map(night).collect::<Vec<_>>();
    nights[39].hrv.quality = "limited";
    nights[40].hrv.value = None;
    nights[40].hrv.quality = "missing";
    let r = calculate(day(40), "UTC", &nights, false);
    assert_eq!(r.metrics[0].baseline.count, 28);
    assert_eq!(r.metrics[1].baseline.count, 27);
    assert_eq!(r.metrics[0].quality, "good");
    assert_eq!(r.metrics[1].quality, "missing");
    assert!(r.metrics[1].relation.is_none());
    assert!(r.metrics[1].history.last().unwrap().value.is_none());
}
#[test]
fn constant_readings_are_similar_and_hrv_uses_log_mean() {
    let mut nights = (0..=14).map(night).collect::<Vec<_>>();
    for (i, n) in nights.iter_mut().enumerate() {
        n.hrv.value = Some(if i % 2 == 0 { 25.0 } else { 100.0 });
    }
    let r = calculate(day(14), "UTC", &nights, false);
    assert_eq!(r.metrics[2].relation, Some("similar"));
    assert!((r.metrics[1].baseline.average.unwrap() - 50.0).abs() < 1e-8);
}
#[test]
fn insufficient_weeks_and_missing_nights_are_explicit() {
    let nights = (0..5).map(night).collect::<Vec<_>>();
    let r = calculate(day(4), "UTC", &nights, false);
    assert!(r.metrics[0].week.average.is_some());
    assert!(r.metrics[0].week.previous_average.is_none());
    assert_eq!(calculate(day(6), "UTC", &nights, false).state, "no_sleep");
    assert_eq!(calculate(day(6), "UTC", &nights, true).state, "updating");
}
#[test]
fn midnight_clock_times_are_close_and_time_zone_changes_suppress_timing() {
    assert!((clock_sd(&[1430.0, 10.0]) - 14.1421356).abs() < 0.001);
    let mut nights = (0..7).map(night).collect::<Vec<_>>();
    assert!(
        calculate(day(6), "UTC", &nights, false)
            .timing
            .asleep_sd_min
            .is_some()
    );
    nights[0].timezone = "Europe/Paris".into();
    assert!(
        calculate(day(6), "UTC", &nights, false)
            .timing
            .asleep_sd_min
            .is_none()
    );
}
#[test]
fn pending_incomplete_and_nonfinite_values_do_not_generate_comparisons() {
    let mut nights = (0..=14).map(night).collect::<Vec<_>>();
    nights[14].state = "awaiting_sync";
    let r = calculate(day(14), "UTC", &nights, false);
    assert!(r.observations.is_empty());
    assert!(r.metrics[0].relation.is_none());
    nights[14].state = "ready";
    nights[0].hrv.value = Some(f64::NAN);
    assert_eq!(
        calculate(day(14), "UTC", &nights, false).metrics[1]
            .baseline
            .count,
        13
    );
}

#[test]
fn meaningful_changes_precede_routine_observations() {
    let mut nights = (0..=14).map(night).collect::<Vec<_>>();
    nights[14].sleep.value = Some(24000.0);
    nights[14].hrv.value = Some(57.0);
    nights[14].resting_hr.value = Some(70.0);
    let r = calculate(day(14), "UTC", &nights, false);
    assert_eq!(r.observations.len(), 2);
    assert!(r.observations[1].contains("resting heart rate"));
}

#[test]
fn outlook_preserves_mixed_signals_and_distinguishes_extent() {
    let mut nights = (0..=14).map(night).collect::<Vec<_>>();
    for n in &mut nights {
        n.hrv.value = Some(50.0);
    }
    let scenarios = [
        (28800.0, 50.0, 55.0, "average", Some(3)),
        (30000.0, 50.0, 55.0, "good", Some(4)),
        (30000.0, 60.0, 52.0, "good", Some(5)),
        (27000.0, 50.0, 55.0, "low", Some(2)),
        (27000.0, 40.0, 60.0, "low", Some(1)),
        (30000.0, 40.0, 55.0, "mixed", None),
    ];
    for (sleep, hrv, hr, state, level) in scenarios {
        nights[14].sleep.value = Some(sleep);
        nights[14].hrv.value = Some(hrv);
        nights[14].resting_hr.value = Some(hr);
        let r = calculate(day(14), "UTC", &nights, false);
        assert_eq!(r.outlook.state, state);
        assert_eq!(r.outlook.level, level);
        assert_eq!(r.outlook.baseline_count, 14);
        assert_eq!(r.outlook.baseline_required, 14);
        assert!(
            (r.metrics[1].comparison.as_ref().unwrap().delta - (hrv / 50.0 - 1.0) * 100.0).abs()
                < 1e-8
        );
        assert_eq!(r.metrics[0].comparison.as_ref().unwrap().unit, "seconds");
        assert_eq!(r.metrics[2].comparison.as_ref().unwrap().unit, "bpm");
    }
}

#[test]
fn outlook_never_turns_early_missing_or_pending_data_into_average() {
    let mut nights = (0..=14).map(night).collect::<Vec<_>>();
    for count in [0, 6, 7, 13] {
        let r = calculate(day(count), "UTC", &nights, false);
        assert_eq!(r.outlook.state, "learning");
        assert_eq!(r.outlook.level, None);
        assert!(
            r.metrics[0]
                .comparison
                .as_ref()
                .is_none_or(|c| c.signal.is_none())
        );
    }
    assert_eq!(
        calculate(day(14), "UTC", &nights, true).outlook.state,
        "updating"
    );
    assert_eq!(
        calculate(day(15), "UTC", &nights, false).outlook.state,
        "no_sleep"
    );
    nights[14].state = "awaiting_sync";
    assert_eq!(
        calculate(day(14), "UTC", &nights, false).outlook.state,
        "awaiting_sync"
    );
    nights[14].state = "ready";
    nights[14].hrv.quality = "limited";
    let r = calculate(day(14), "UTC", &nights, false);
    assert_eq!(r.outlook.state, "limited");
    assert!(r.metrics[1].comparison.is_none());
    nights[14].hrv.quality = "good";
    nights[14].hrv.value = Some(f64::NAN);
    assert_eq!(
        calculate(day(14), "UTC", &nights, false).outlook.state,
        "limited"
    );
}
