use super::*;
fn date(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
fn readings(values: &[f64]) -> Vec<WeightDay> {
    values
        .iter()
        .enumerate()
        .flat_map(|(week, kg)| {
            (0..7).map(move |n| WeightDay {
                day: date("2025-01-06") + Duration::days(week as i64 * 7 + n),
                kg: *kg,
            })
        })
        .collect()
}
fn result(rows: &[WeightDay], target: f64) -> WeightOutlook {
    weight_outlook(
        rows,
        date("2025-01-27"),
        date("2025-01-06"),
        date("2025-01-06"),
        target,
    )
}
#[test]
fn median_resists_one_spike_and_uses_even_middle_pair() {
    assert_eq!(median(vec![1., 100., 3., 2.]), Some(2.5));
    let mut rows = readings(&[63., 62.7, 62.4]);
    rows.last_mut().unwrap().kg = 70.;
    let r = result(&rows, 0.3);
    assert_eq!(r.state, "on_pace");
    assert_eq!(r.median_kg, Some(62.4));
    assert!((r.change_kg.unwrap() + 0.3).abs() < 1e-9);
}
#[test]
fn target_band_is_inclusive_and_configurable() {
    for delta in [0.2, 0.3, 0.4] {
        assert_eq!(
            result(&readings(&[63., 63. - delta, 63. - delta * 2.]), 0.3).state,
            "on_pace"
        );
    }
    assert_eq!(
        result(&readings(&[63., 62.7, 62.4]), 0.6).state,
        "below_pace"
    );
    assert_eq!(result(&readings(&[63., 62.7, 62.4]), 0.1).state, "faster");
}
#[test]
fn one_bad_week_is_not_a_stall() {
    assert_eq!(result(&readings(&[63., 62.7, 63.5]), 0.3).state, "unclear");
    assert_eq!(
        result(&readings(&[63., 62.7, 62.7]), 0.3).state,
        "slower_week"
    );
    assert_eq!(
        result(&readings(&[63., 62.7, 62.]), 0.3).state,
        "faster_week"
    );
}
#[test]
fn persistent_slow_fast_flat_and_gain_are_distinct() {
    for (values, status) in [
        ([63., 62.9, 62.8], "below_pace"),
        ([63., 62.4, 61.8], "faster"),
        ([63., 63.02, 63.01], "possible_stall"),
        ([63., 63.3, 63.6], "below_pace"),
    ] {
        assert_eq!(result(&readings(&values), 0.3).state, status);
    }
}
#[test]
fn low_target_does_not_reward_flatness_as_on_pace() {
    assert_eq!(
        result(&readings(&[63., 63., 63.]), 0.1).state,
        "possible_stall"
    );
}
#[test]
fn sparse_or_clustered_weeks_never_get_a_verdict() {
    let rows = readings(&[63., 62.7, 62.4]);
    let sparse: Vec<_> = rows
        .iter()
        .filter(|d| d.day.weekday().num_days_from_monday() < 3)
        .cloned()
        .collect();
    assert_eq!(result(&sparse, 0.3).state, "insufficient");
    let clustered: Vec<_> = rows
        .iter()
        .filter(|d| d.day.weekday().num_days_from_monday() < 4)
        .cloned()
        .collect();
    assert_eq!(result(&clustered, 0.3).state, "insufficient");
    let spread: Vec<_> = rows
        .into_iter()
        .filter(|d| [0, 2, 4, 6].contains(&d.day.weekday().num_days_from_monday()))
        .collect();
    assert_eq!(result(&spread, 0.3).state, "on_pace");
}
#[test]
fn duplicates_do_not_count_as_extra_days() {
    let rows = readings(&[63., 62.7, 62.4]);
    let mut doubled = rows.clone();
    doubled.extend(rows);
    assert_eq!(result(&doubled, 0.3).count, 7);
}
#[test]
fn ignores_invalid_future_and_pre_goal_values() {
    let mut rows = readings(&[63., 62.7, 62.4]);
    rows.extend([
        WeightDay {
            day: date("2025-01-05"),
            kg: 200.,
        },
        WeightDay {
            day: date("2025-01-28"),
            kg: 20.,
        },
        WeightDay {
            day: date("2025-01-20"),
            kg: f64::NAN,
        },
    ]);
    assert_eq!(result(&rows, 0.3).state, "on_pace");
}
#[test]
fn missing_middle_week_never_bridges_a_stall() {
    let rows: Vec<_> = readings(&[63., 63., 63.])
        .into_iter()
        .filter(|r| r.day < date("2025-01-13") || r.day >= date("2025-01-20"))
        .collect();
    let r = result(&rows, 0.3);
    assert_eq!(r.state, "insufficient");
    assert_eq!(r.change_kg, None);
    assert_eq!(r.weeks[6].median_kg, None);
}
#[test]
fn first_week_and_changed_target_reset_comparison() {
    let rows = readings(&[63., 62.7, 62.4]);
    for since in ["2025-01-23", "2025-01-27"] {
        let r = weight_outlook(
            &rows,
            date("2025-01-27"),
            date("2025-01-06"),
            date(since),
            0.3,
        );
        assert_eq!(r.state, "starting");
        assert_eq!(r.change_kg, None);
    }
}
#[test]
fn sunday_is_provisional_monday_keeps_same_week_and_late_edits_recompute() {
    let rows = readings(&[63., 62.7, 62.4]);
    let sunday = weight_outlook(
        &rows,
        date("2025-01-26"),
        date("2025-01-06"),
        date("2025-01-06"),
        0.3,
    );
    let monday = result(&rows, 0.3);
    assert!(sunday.provisional);
    assert!(!monday.provisional);
    assert_eq!(sunday.start, monday.start);
    assert_eq!(sunday.median_kg, monday.median_kg);
    assert_eq!(
        result(&readings(&[63., 62.7, 62.9]), 0.3).median_kg,
        Some(62.9)
    );
}
#[test]
fn calendar_year_boundary_and_empty_history() {
    let r = weight_outlook(
        &[],
        date("2026-01-01"),
        date("2025-12-01"),
        date("2025-12-01"),
        0.3,
    );
    assert_eq!(r.start, date("2025-12-22"));
    assert_eq!(r.end, date("2025-12-28"));
    assert_eq!(r.state, "insufficient");
    assert_eq!(r.median_kg, None);
}
