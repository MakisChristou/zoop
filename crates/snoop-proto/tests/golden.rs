//! Decodes the MIT-licensed wearable5.0 golden vectors and checks R18 fields.

use serde::Deserialize;
use snoop_proto::{Decoded, Record, decode_frame};

#[derive(Deserialize)]
struct Vector {
    name: String,
    hex: String,
    expected: serde_json::Value,
}

fn vectors() -> Vec<Vector> {
    serde_json::from_str(include_str!("fixtures/wearable5_golden.json"))
        .expect("golden.json parses")
}

#[test]
fn every_golden_frame_passes_envelope_check() {
    for vector in vectors() {
        let bytes = hex::decode(&vector.hex).unwrap();
        decode_frame(&bytes).unwrap_or_else(|error| panic!("{}: {error}", vector.name));
    }
}

#[test]
fn r18_fields_match_expected() {
    let mut checked = 0;
    for vector in vectors() {
        if vector
            .expected
            .get("layout")
            .and_then(|layout| layout.as_u64())
            != Some(18)
        {
            continue;
        }
        let bytes = hex::decode(&vector.hex).unwrap();
        let Decoded::Record {
            record: Record::Biometric(record),
            ..
        } = decode_frame(&bytes).unwrap()
        else {
            panic!("{}: expected a biometric record", vector.name);
        };
        let expected = &vector.expected;
        let name = &vector.name;

        assert_eq!(
            u64::from(record.heart_rate.bpm),
            expected["heart_rate"].as_u64().unwrap(),
            "{name} hr"
        );
        assert_eq!(
            u64::from(record.unix_seconds),
            expected["unix_s"].as_u64().unwrap(),
            "{name} unix"
        );
        if let Some(rr) = expected["rr_ms"].as_array() {
            let want: Vec<u32> = rr.iter().map(|x| x.as_u64().unwrap() as u32).collect();
            assert_eq!(record.heart_rate.rr_ms, want, "{name} rr");
        }
        if let Some(steps) = expected["step_counter"].as_u64() {
            assert_eq!(record.steps.map(u64::from), Some(steps), "{name} steps");
        }
        if let Some(temp) = expected["skin_temp_c"].as_f64() {
            let got = f64::from(record.skin_temp_c.expect("skin temp present"));
            assert!(
                (got - temp).abs() < 0.05,
                "{name} skin temp {got} vs {temp}"
            );
        }
        checked += 1;
    }
    assert!(checked > 0, "no R18 vectors found");
}
