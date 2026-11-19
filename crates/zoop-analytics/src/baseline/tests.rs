use super::*;

#[test]
fn converges_toward_constant_input() {
    let mut baseline = Baseline::default();
    for _ in 0..50 {
        baseline.update(60.0, 0.25);
    }
    assert!((baseline.mean - 60.0).abs() < 1e-9);
}

#[test]
fn z_score_needs_history_and_spread() {
    let mut baseline = Baseline::default();
    baseline.update(60.0, 0.25);
    assert_eq!(baseline.z_score(70.0), None);
    for value in [58.0, 62.0, 59.0, 61.0] {
        baseline.update(value, 0.25);
    }
    assert!(baseline.z_score(70.0).unwrap() > 0.0);
}
