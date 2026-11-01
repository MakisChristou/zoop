use super::*;
use chrono::Duration;
fn at(s: i64) -> DateTime<Utc> {
    DateTime::from_timestamp(s, 0).unwrap()
}
fn physiology() -> Physiology {
    Physiology {
        hr_max: 190.,
        resting_hr: 60.,
        body: None,
    }
}
#[test]
fn split_is_half_open_and_missing_data_is_not_zero() {
    let samples: Vec<_> = (0..120)
        .map(|i| ActivitySample {
            ts: at(i),
            hr: (i < 60).then_some(140),
            steps: Some(i as i32),
            activity: Some(1),
            motion_g: None,
            band_state: 0,
        })
        .collect();
    let all = summarize_interval(&samples, at(0), at(120), &physiology());
    let left = summarize_interval(&samples, at(0), at(60), &physiology());
    let right = summarize_interval(&samples, at(60), at(120), &physiology());
    assert_eq!(left.coverage_s + right.coverage_s, all.coverage_s);
    assert_eq!(
        left.steps.unwrap() + right.steps.unwrap(),
        all.steps.unwrap()
    );
    assert_eq!(right.load, None);
    assert_eq!(right.zones, None);
    assert_eq!(right.hr_coverage_s, 0);
    assert_eq!(all.hr_coverage_s, 60);
    assert!(all.kcal.is_none());
    let empty = summarize_interval(&samples, at(200), at(210), &physiology());
    assert_eq!(empty.coverage_s, 0);
    assert_eq!(empty.steps, None);
    assert_eq!(empty.load, None);
}
#[test]
fn rest_readings_contribute_but_missing_seconds_are_not_filled() {
    let samples: Vec<_> = [0, 1, 60, 61]
        .into_iter()
        .map(|i| ActivitySample {
            ts: at(i),
            hr: Some(120),
            steps: None,
            activity: Some(0),
            motion_g: None,
            band_state: 0,
        })
        .collect();
    let m = summarize_interval(&samples, at(0), at(120), &physiology());
    assert_eq!(m.coverage_s, 4);
    assert_eq!(m.hr_coverage_s, 4);
    assert_eq!(m.avg_hr, Some(120.));
    assert_eq!(m.steps, None);
}
#[test]
fn overlapping_and_nested_ownership_never_leaks_trimmed_fragments() {
    let scopes = [(at(20), at(40)), (at(35), at(60)), (at(25), at(30))];
    assert_eq!(
        unclaimed_intervals(at(0), at(100), &scopes),
        vec![(at(0), at(20)), (at(60), at(100))]
    );
    assert!(
        unclaimed_intervals(at(0), at(100), &[(at(0) - Duration::seconds(1), at(101))]).is_empty()
    );
}
