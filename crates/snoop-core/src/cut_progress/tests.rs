use super::*;
fn day(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
fn rows(xs: &[(&str, f64)]) -> Vec<WeightDay> {
    xs.iter()
        .map(|(d, kg)| WeightDay {
            day: day(d),
            kg: *kg,
        })
        .collect()
}
#[test]
fn target_and_remaining_use_calendar_days_and_partial_weeks() {
    let start = day("2026-11-16");
    let end = day("2027-01-11");
    let base = rows(&[("2026-11-16", 70.0)]);
    let p = cut_progress(&base, &base, start, start, Some(end), 0.3);
    assert_eq!(p.weeks_remaining, Some(8));
    assert_eq!(p.target_weight_kg, Some(67.6));
    assert_eq!(p.total_lost_kg, Some(0.0));
    assert_eq!(
        cut_progress(&base, &[], day("2026-11-17"), start, Some(end), 0.3).weeks_remaining,
        Some(8)
    );
}
#[test]
fn baseline_is_robust_and_target_change_keeps_start() {
    let base = rows(&[
        ("2026-11-10", 70.0),
        ("2026-11-12", 70.2),
        ("2026-11-16", 90.0),
    ]);
    let recent = rows(&[
        ("2026-12-07", 68.0),
        ("2026-12-08", 68.2),
        ("2026-12-09", 80.0),
    ]);
    let p = cut_progress(
        &base,
        &recent,
        day("2026-12-09"),
        day("2026-11-16"),
        Some(day("2027-01-11")),
        0.4,
    );
    assert_eq!(p.starting_weight_kg, Some(70.2));
    assert_eq!(p.current_weight_kg, Some(68.2));
    assert!((p.total_lost_kg.unwrap() - 2.0).abs() < 1e-9);
    assert_eq!(p.target_weight_kg, Some(67.0));
}
#[test]
fn ended_cut_freezes_at_finish_and_does_not_call_gains_loss() {
    let base = rows(&[("2026-11-16", 70.0)]);
    let recent = rows(&[("2026-11-30", 71.0), ("2026-12-01", 60.0)]);
    let p = cut_progress(
        &base,
        &recent,
        day("2026-12-10"),
        day("2026-11-16"),
        Some(day("2026-11-30")),
        0.3,
    );
    assert!(p.completed);
    assert_eq!(p.weeks_remaining, Some(0));
    assert_eq!(p.total_lost_kg, Some(-1.0));
    assert!(
        !cut_progress(
            &base,
            &recent,
            day("2026-11-30"),
            day("2026-11-16"),
            Some(day("2026-11-30")),
            0.3
        )
        .completed
    );
}
#[test]
fn missing_stale_future_and_duplicate_readings_are_not_fabricated() {
    let base = rows(&[
        ("2026-11-01", 70.0),
        ("2026-11-17", 69.5),
        ("2026-11-17", 100.0),
        ("2026-11-18", 68.0),
    ]);
    let p = cut_progress(&base, &[], day("2026-11-17"), day("2026-11-16"), None, 0.3);
    assert_eq!(p.starting_weight_kg, Some(69.5));
    assert_eq!(p.total_lost_kg, None);
    assert_eq!(p.target_weight_kg, None);
    assert_eq!(p.weeks_remaining, None);
    let p = cut_progress(
        &base,
        &base,
        day("2026-11-16"),
        day("2026-11-16"),
        Some(day("2026-12-16")),
        0.3,
    );
    assert_eq!(p.starting_weight_kg, None);
    assert_eq!(p.total_lost_kg, None);
}
#[test]
fn leap_day_and_unreasonable_projection_stay_well_defined() {
    let base = rows(&[("2028-02-28", 70.0)]);
    let p = cut_progress(
        &base,
        &base,
        day("2028-02-28"),
        day("2028-02-28"),
        Some(day("2028-03-06")),
        0.3,
    );
    assert_eq!(p.weeks_remaining, Some(1));
    assert_eq!(p.target_weight_kg, Some(69.7));
    assert_eq!(
        cut_progress(
            &base,
            &base,
            day("2028-02-28"),
            day("2028-02-28"),
            Some(day("2030-02-28")),
            1.0
        )
        .target_weight_kg,
        None
    );
}
