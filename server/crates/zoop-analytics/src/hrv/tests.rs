use super::*;

#[test]
fn rmssd_of_constant_series_is_zero() {
    assert_eq!(rmssd(&[1000.0, 1000.0, 1000.0]), Some(0.0));
}

#[test]
fn rmssd_known_value() {
    // diffs 20, -20, 20 -> squares 400 each -> mean 400 -> sqrt 20
    let value = rmssd(&[1000.0, 1020.0, 1000.0, 1020.0]).unwrap();
    assert!((value - 20.0).abs() < 1e-9);
}

#[test]
fn clean_rr_drops_outliers() {
    let cleaned = clean_rr(&[1000, 1010, 100, 3000, 1500, 1005]);
    assert_eq!(cleaned, vec![1000.0, 1010.0, 1005.0]);
}

#[test]
fn too_few_intervals_yield_none() {
    assert_eq!(rmssd(&[1000.0]), None);
    assert_eq!(sdnn(&[]), None);
}
