use super::*;
fn date(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
#[test]
fn windows_exclude_today_and_do_not_shift_on_leap_days() {
    let result = calculate(date("2024-03-01"), "UTC", &[], &[]);
    assert_eq!(result.current.start, date("2024-02-02"));
    assert_eq!(result.current.end, date("2024-02-29"));
    assert_eq!(result.previous.end, date("2024-02-01"));
    assert!(
        result
            .metrics
            .iter()
            .all(|m| m.current.is_none() && m.change.is_none() && m.weeks.len() == 8)
    );
}
#[test]
fn missing_data_is_not_zero_and_comparison_requires_both_windows() {
    let mut values = vec![Some(100.0); 56];
    values[0] = Some(0.0);
    for value in &mut values[28..36] {
        *value = None;
    }
    let m = metric("steps", &values, false, false);
    assert_eq!(m.current, Some(100.0));
    assert_eq!(m.current_count, 20);
    assert!(m.change.is_none());
    assert!(m.weeks[4].is_none());
    values[35] = Some(200.0);
    let m = metric("steps", &values, false, false);
    assert_eq!(m.current_count, 21);
    assert!(m.change.unwrap() > 0.0);
    assert!((m.previous.unwrap() - 2700.0 / 28.0).abs() < 0.0001);
}
#[test]
fn weekly_totals_use_complete_weeks_only() {
    let mut v = vec![Some(10.0); 56];
    v[30] = None;
    let m = metric("walking", &v, true, false);
    assert_eq!(m.current, Some(70.0));
    assert_eq!(m.current_count, 3);
    assert_eq!(m.change, Some(0.0));
    v[40] = None;
    assert!(metric("walking", &v, true, false).change.is_none());
}
#[test]
fn wake_variation_handles_midnight_and_constant_times() {
    assert!(wake_variation(&[1435.0, 5.0]).unwrap() < 5.1);
    assert!(wake_variation(&[600.0; 28]).unwrap() < 0.001);
    assert!(wake_variation(&[600.0]).is_none());
}
#[test]
fn quality_gate_uses_actual_day_length_and_excludes_pending_strength() {
    let today = date("2025-03-31");
    let day = ProgressDay {
        day: today - Duration::days(1),
        samples: 62100,
        day_seconds: 82800.0,
        steps: Some(0),
        walking_s: Some(0),
        strength: true,
        pending: true,
    };
    let r = calculate(today, "Europe/Berlin", &[], &[day]);
    assert_eq!(r.metrics[2].current, Some(0.0));
    assert_eq!(r.metrics[4].current_count, 0);
    let incomplete = ProgressDay {
        day: today - Duration::days(1),
        samples: 100,
        day_seconds: 86400.0,
        steps: Some(12000),
        walking_s: Some(1000),
        strength: false,
        pending: false,
    };
    assert!(
        calculate(today, "UTC", &[], &[incomplete]).metrics[2]
            .current
            .is_none()
    );
}
#[test]
fn daily_mean_is_not_an_unweighted_mean_of_week_means() {
    let mut v = vec![Some(100.0); 56];
    for item in &mut v[28..31] {
        *item = None;
    }
    v[31] = Some(1000.0);
    let m = metric("steps", &v, false, false);
    assert_eq!(m.current, Some(136.0));
}
