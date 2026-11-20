use super::*;
use chrono::{TimeZone, Utc};
fn goal(phase: &str, rate: f64) -> zoop_storage::WeightGoal {
    let start = Utc.with_ymd_and_hms(2026, 1, 5, 0, 0, 0).unwrap();
    zoop_storage::WeightGoal {
        id: 1,
        revision: 1,
        phase: phase.into(),
        maintenance_reference_kg: Some(64.0),
        maintenance_range_pct: 1.0,
        active: true,
        started_at: start,
        pace_started_at: start,
        timezone: "UTC".into(),
        weekly_loss_kg: rate,
        reminder_enabled: true,
        reminder_weekday: 1,
        reminder_minute: 1200,
        updated_at: start,
        finish_date: None,
        daily_steps_goal: None,
    }
}
fn readings(medians: &[f64]) -> Vec<WeightDay> {
    let start = NaiveDate::from_ymd_opt(2026, 1, 5).unwrap();
    medians
        .iter()
        .enumerate()
        .flat_map(|(i, kg)| {
            [0, 1, 3, 5, 6].map(|j| WeightDay {
                day: start + Duration::days(i as i64 * 7 + j),
                kg: *kg,
            })
        })
        .collect()
}
fn result(phase: &str, rate: f64, medians: &[f64]) -> WeightOutlook {
    let g = goal(phase, rate);
    let d = readings(medians);
    phase_outlook(
        &d,
        d.last().unwrap().day,
        g.started_at.date_naive(),
        g.started_at.date_naive(),
        &g,
    )
}
#[test]
fn phase_scenarios() {
    for (phase, rate, weights, state) in [
        ("cut", 0.4, vec![64.0, 64.4, 63.2], "on_pace"),
        ("cut", 0.4, vec![64.0, 64.0, 64.0], "possible_stall"),
        ("bulk", 0.2, vec![64.0, 64.2, 64.4], "on_pace"),
        ("bulk", 0.2, vec![64.0, 64.6, 65.2], "above_pace"),
        ("bulk", 0.05, vec![64.0, 64.0, 64.0], "possible_stall"),
        ("cut", 0.4, vec![64.0, 64.0, 63.6, 63.6], "below_pace"),
        ("maintenance", 0.0, vec![64.0, 64.7, 64.1], "stable"),
        ("maintenance", 0.0, vec![64.0, 64.2, 64.4], "drifting_up"),
        ("maintenance", 0.0, vec![64.0, 63.8, 63.6], "drifting_down"),
        ("maintenance", 0.0, vec![64.0, 65.0, 65.0], "above_range"),
        ("maintenance", 0.0, vec![64.0, 63.0, 63.0], "below_range"),
        ("maintenance", 0.0, vec![64.0, 64.0], "building_trend"),
        ("cut", 0.4, vec![64.0, 63.6, 64.5], "watching"),
        ("cut", 0.4, vec![64.0, 64.0, 64.0, 63.2], "on_pace"),
    ] {
        assert_eq!(
            result(phase, rate, &weights).state,
            state,
            "{phase} {weights:?}"
        );
    }
}
#[test]
fn sparse_gap_duplicates_and_outside_readings_do_not_create_confidence() {
    let g = goal("cut", 0.3);
    let mut d = readings(&[64.0, 63.7, 63.4]);
    let today = d.last().unwrap().day;
    let start = g.started_at.date_naive();
    d.extend(d.clone());
    assert_eq!(phase_outlook(&d, today, start, start, &g).count, 5);
    d.retain(|r| !(r.day >= start + Duration::days(7) && r.day < start + Duration::days(14)));
    assert_eq!(
        phase_outlook(&d, today, start, start, &g).state,
        "building_trend"
    );
    d.push(WeightDay {
        day: today + Duration::days(1),
        kg: 100.0,
    });
    assert_eq!(
        phase_outlook(&d, today, start, start, &g).state,
        "building_trend"
    );
}
#[test]
fn symmetry_translation_and_outlier_resistance() {
    for rate in [0.05, 0.1, 0.2, 0.4, 1.0] {
        for delta in [0.0, 0.05, 0.15, 0.4, 0.8] {
            let cut = result("cut", rate, &[64.0, 64.0 - delta, 64.0 - 2.0 * delta]);
            let bulk = result("bulk", rate, &[64.0, 64.0 + delta, 64.0 + 2.0 * delta]);
            assert_eq!(cut.state, bulk.state);
            assert_eq!(
                cut.state,
                result("cut", rate, &[74.0, 74.0 - delta, 74.0 - 2.0 * delta]).state
            );
        }
    }
    let g = goal("cut", 0.4);
    let mut d = readings(&[64.0, 63.6, 63.2]);
    let today = d.last().unwrap().day;
    d.last_mut().unwrap().kg = 80.0;
    let r = phase_outlook(
        &d,
        today,
        g.started_at.date_naive(),
        g.started_at.date_naive(),
        &g,
    );
    assert_eq!(r.state, "on_pace");
}
#[test]
fn inclusive_tolerance_and_reference_required() {
    assert_eq!(result("cut", 0.4, &[64.0, 63.7, 63.4]).state, "on_pace");
    let mut g = goal("maintenance", 0.0);
    g.maintenance_reference_kg = None;
    let d = readings(&[64.0, 64.0, 64.0]);
    assert_eq!(
        phase_outlook(
            &d,
            d.last().unwrap().day,
            g.started_at.date_naive(),
            g.started_at.date_naive(),
            &g
        )
        .state,
        "building_trend"
    );
}

#[test]
fn phase_retains_older_weeks_without_compressing_time() {
    let medians = vec![64.0; 52];
    let r = result("maintenance", 0.0, &medians);
    assert_eq!(r.weeks.len(), 52);
    assert_eq!(r.state, "stable");
    assert_eq!(
        (r.weeks.last().unwrap().start - r.weeks[0].start).num_days(),
        51 * 7
    );
}
