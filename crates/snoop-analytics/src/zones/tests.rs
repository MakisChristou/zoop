use super::*;

#[test]
fn tanaka_prediction_and_observed_override() {
    assert!((predicted_hr_max(30.0) - 187.0).abs() < 1e-9);
    assert_eq!(hr_max(Some(30.0), None), Some(187.0));
    assert_eq!(hr_max(None, Some(190.0)), Some(190.0));
    assert_eq!(hr_max(Some(30.0), Some(180.0)), Some(187.0));
    assert_eq!(hr_max(Some(30.0), Some(195.0)), Some(195.0));
    assert_eq!(hr_max(None, None), None);
}

#[test]
fn zone_boundaries_are_inclusive_at_the_bottom() {
    let max = 200.0;
    assert_eq!(zone_of(99.0, max), None);
    assert_eq!(zone_of(100.0, max), Some(0));
    assert_eq!(zone_of(119.9, max), Some(0));
    assert_eq!(zone_of(120.0, max), Some(1));
    assert_eq!(zone_of(140.0, max), Some(2));
    assert_eq!(zone_of(160.0, max), Some(3));
    assert_eq!(zone_of(180.0, max), Some(4));
    assert_eq!(zone_of(210.0, max), Some(4));
    assert_eq!(zone_of(150.0, 0.0), None);
}

#[test]
fn trimp_weights_minutes_by_zone() {
    let mut zones = ZoneSeconds::default();
    for _ in 0..600 {
        zones.add(110.0, 200.0);
    }
    for _ in 0..300 {
        zones.add(185.0, 200.0);
    }
    for _ in 0..30 {
        zones.add(80.0, 200.0);
    }
    assert_eq!(zones.0, [600, 0, 0, 0, 300]);
    assert_eq!(zones.minutes(), [10, 0, 0, 0, 5]);
    assert_eq!(zones.total(), 900);
    assert!((zones.trimp() - 35.0).abs() < 1e-9);

    let mut other = ZoneSeconds([0, 60, 0, 0, 0]);
    other.merge(&zones);
    assert_eq!(other.0, [600, 60, 0, 0, 300]);
}

#[test]
fn karvonen_threshold() {
    assert!((hr_reserve_threshold(55.0, 190.0, 0.4) - 109.0).abs() < 1e-9);
}

#[test]
fn load_is_zero_at_rest_monotone_and_capped() {
    assert_eq!(load(0.0), 0.0);
    assert_eq!(load(-5.0), 0.0);
    let walk = load(50.0);
    let gym = load(200.0);
    assert!(walk > 5.0 && walk < 7.5, "walk {walk}");
    assert!(gym > 14.0 && gym < 17.0, "gym {gym}");
    assert!((load(LOAD_SCALE) - LOAD_MAX * (1.0 - std::f64::consts::E.powi(-1))).abs() < 1e-9);
    assert!(load(1e9) <= LOAD_MAX);
    assert!(load(1e9) > LOAD_MAX - 1e-6);
}
