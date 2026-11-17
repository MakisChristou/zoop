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
fn first_and_latest_cut_readings_replace_pre_cut_and_current_medians() {
    let data = rows(&[
        ("2026-11-10", 69.9),
        ("2026-11-15", 70.4),
        ("2026-11-16", 70.6),
        ("2026-11-17", 69.9),
    ]);
    let p = cut_progress(
        &data,
        day("2026-11-17"),
        day("2026-11-16"),
        Some(day("2026-12-10")),
        0.8,
    );
    assert_eq!(p.starting_weight_kg, Some(70.6));
    assert_eq!(p.current_weight_kg, Some(69.9));
    assert!((p.total_lost_kg.unwrap() - 0.7).abs() < 1e-9);
    assert!((p.target_weight_kg.unwrap() - (70.6 - 0.8 * 24.0 / 7.0)).abs() < 1e-9);
    assert_eq!(p.weeks_remaining, Some(4));
}
#[test]
fn single_cut_reading_means_zero_change_not_a_pre_cut_gain() {
    let data = rows(&[("2026-11-15", 60.0), ("2026-11-16", 70.0)]);
    let p = cut_progress(
        &data,
        day("2026-11-16"),
        day("2026-11-16"),
        Some(day("2027-01-11")),
        0.3,
    );
    assert_eq!(p.total_lost_kg, Some(0.0));
    assert_eq!(p.target_weight_kg, Some(67.6));
    assert_eq!(p.weeks_remaining, Some(8));
}
#[test]
fn pace_change_recalculates_target_without_replacing_start_weight() {
    let data = rows(&[("2026-11-16", 70.0), ("2026-12-09", 68.0)]);
    let p = cut_progress(
        &data,
        day("2026-12-09"),
        day("2026-11-16"),
        Some(day("2027-01-11")),
        0.4,
    );
    assert_eq!(p.total_lost_kg, Some(2.0));
    assert_eq!(p.target_weight_kg, Some(66.8));
}
#[test]
fn finished_cut_excludes_later_weights_and_reports_real_gains() {
    let data = rows(&[
        ("2026-11-16", 70.0),
        ("2026-11-30", 71.0),
        ("2026-12-01", 60.0),
    ]);
    let p = cut_progress(
        &data,
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
            &data,
            day("2026-11-30"),
            day("2026-11-16"),
            Some(day("2026-11-30")),
            0.3
        )
        .completed
    );
}
#[test]
fn delayed_first_reading_and_long_logging_gaps_still_use_real_endpoints() {
    let data = rows(&[("2026-01-20", 80.0), ("2026-06-01", 78.0)]);
    let p = cut_progress(
        &data,
        day("2026-12-31"),
        day("2026-01-01"),
        Some(day("2026-12-31")),
        0.1,
    );
    assert_eq!(p.starting_weight_kg, Some(80.0));
    assert_eq!(p.current_weight_kg, Some(78.0));
    assert_eq!(p.total_lost_kg, Some(2.0));
}
#[test]
fn missing_future_invalid_and_pre_cut_weights_do_not_create_progress() {
    let data = rows(&[
        ("2026-11-15", 70.0),
        ("2026-11-16", f64::NAN),
        ("2026-11-17", f64::INFINITY),
        ("2026-11-17", 19.0),
        ("2026-11-18", 69.0),
    ]);
    let p = cut_progress(
        &data,
        day("2026-11-17"),
        day("2026-11-16"),
        Some(day("2026-12-10")),
        0.3,
    );
    assert!(p.weigh_ins.is_empty());
    assert_eq!(p.starting_weight_kg, None);
    assert_eq!(p.current_weight_kg, None);
    assert_eq!(p.total_lost_kg, None);
    assert_eq!(p.target_weight_kg, None);
}
#[test]
fn input_order_and_duplicate_days_preserve_canonical_first_row() {
    let data = rows(&[
        ("2026-11-18", 69.0),
        ("2026-11-16", 70.0),
        ("2026-11-16", 90.0),
        ("2026-11-17", 71.0),
    ]);
    let p = cut_progress(&data, day("2026-11-18"), day("2026-11-16"), None, 0.3);
    assert_eq!(
        p.weigh_ins
            .iter()
            .map(|p| (p.day, p.kg))
            .collect::<Vec<_>>(),
        vec![
            (day("2026-11-16"), 70.0),
            (day("2026-11-17"), 71.0),
            (day("2026-11-18"), 69.0)
        ]
    );
    assert_eq!(p.total_lost_kg, Some(1.0));
    assert_eq!(p.target_weight_kg, None);
    assert_eq!(p.weeks_remaining, None);
}
#[test]
fn leap_day_and_unreasonable_projection_stay_well_defined() {
    let data = rows(&[("2028-02-28", 70.0)]);
    let p = cut_progress(
        &data,
        day("2028-02-28"),
        day("2028-02-28"),
        Some(day("2028-03-06")),
        0.3,
    );
    assert_eq!(p.weeks_remaining, Some(1));
    assert_eq!(p.target_weight_kg, Some(69.7));
    assert_eq!(
        cut_progress(
            &data,
            day("2028-02-28"),
            day("2028-02-28"),
            Some(day("2030-02-28")),
            1.0
        )
        .target_weight_kg,
        None
    );
    for rate in [f64::NAN, f64::INFINITY, 0.0, -0.3] {
        assert_eq!(
            cut_progress(
                &data,
                day("2028-02-28"),
                day("2028-02-28"),
                Some(day("2028-03-06")),
                rate
            )
            .target_weight_kg,
            None
        );
    }
}
