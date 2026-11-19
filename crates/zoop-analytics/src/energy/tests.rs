use super::*;

fn male() -> Body {
    Body {
        sex: Sex::Male,
        age_years: 30.0,
        weight_kg: 80.0,
    }
}

fn female() -> Body {
    Body {
        sex: Sex::Female,
        age_years: 30.0,
        weight_kg: 60.0,
    }
}

#[test]
fn keytel_equations_by_hand() {
    // −55.0969 + 0.6309·150 + 0.1988·80 + 0.2017·30 = 61.4931 kJ/min
    let kj = kj_per_minute(&male(), 150.0);
    assert!((kj - 61.4931).abs() < 1e-3, "{kj}");
    assert!((kcal_per_minute(&male(), 150.0) - 61.4931 / 4.184).abs() < 1e-3);
    // −20.4022 + 0.4472·150 − 0.1263·60 + 0.074·30 = 41.3198 kJ/min
    let kj = kj_per_minute(&female(), 150.0);
    assert!((kj - 41.3198).abs() < 1e-3, "{kj}");
}

#[test]
fn predictions_below_zero_are_clamped() {
    assert_eq!(kj_per_minute(&male(), 50.0), 0.0);
    assert_eq!(kcal_per_minute(&male(), 40.0), 0.0);
}

#[test]
fn sums_over_seconds() {
    let ten_minutes = std::iter::repeat_n(150.0, 600);
    let kcal = kcal_over_seconds(&male(), ten_minutes);
    assert!((kcal - 10.0 * 61.4931 / 4.184).abs() < 1e-6, "{kcal}");
}

#[test]
fn sex_parses_stored_values() {
    assert_eq!(Sex::parse("male"), Some(Sex::Male));
    assert_eq!(Sex::parse("female"), Some(Sex::Female));
    assert_eq!(Sex::parse("other"), None);
}
