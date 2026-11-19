//! Real frames from our own WHOOP MG. Guards the decoder against drifting from hardware.

use serde::Deserialize;
use zoop_proto::{
    ActivityClass, BandState, Command, Decoded, Layout, MetadataKind, PacketType, ResultCode,
    decode_frame,
};

#[derive(Deserialize)]
struct Capture {
    name: String,
    hex: String,
}

fn capture(name: &str) -> Vec<u8> {
    let captures: Vec<Capture> =
        serde_json::from_str(include_str!("fixtures/mg_capture.json")).expect("fixtures parse");
    let entry = captures
        .iter()
        .find(|c| c.name == name)
        .expect("fixture exists");
    hex::decode(&entry.hex).expect("fixture is hex")
}

#[test]
fn every_capture_is_a_valid_frame() {
    let captures: Vec<Capture> =
        serde_json::from_str(include_str!("fixtures/mg_capture.json")).unwrap();
    for c in captures {
        decode_frame(&hex::decode(&c.hex).unwrap()).unwrap_or_else(|e| panic!("{}: {e}", c.name));
    }
}

#[test]
fn r18_daytime_record() {
    let Decoded::Biometric(b) = decode_frame(&capture("r18_daytime")).unwrap() else {
        panic!("expected biometric");
    };
    assert_eq!(b.header.layout, Layout::Biometric);
    assert_eq!(b.header.unix_s, 1_792_780_655); // 2026-10-23 18:37:35 UTC
    assert_eq!(b.heart_rate, 76);
    assert!(b.rr_ms.is_empty(), "no R-R while moving");
    assert_eq!(b.band_state, BandState::Wake);
    assert_eq!(b.activity, ActivityClass::Still);
    assert_eq!(b.steps, 6108);
    assert!((b.skin_temp_c.unwrap() - 32.45).abs() < 0.01);
    assert_eq!(b.spo2_percent, None);
    assert!(b.gravity_g.is_some());
}

#[test]
fn r26_is_preserved_as_unknown_layout() {
    let Decoded::UnknownRecord(u) = decode_frame(&capture("r26_compact_optical")).unwrap() else {
        panic!("expected unknown record");
    };
    assert_eq!(u.header.layout, Layout::CompactOptical);
    assert_eq!(u.frame_len, 88);
}

#[test]
fn hello_response_event_metadata_console() {
    let Decoded::CommandResponse(r) = decode_frame(&capture("hello_response")).unwrap() else {
        panic!("expected response");
    };
    assert_eq!(r.command, Command::GetHello.code());
    assert_eq!(
        r.result,
        ResultCode::Pending,
        "first of two hello replies is PENDING"
    );
    assert_eq!(r.origin_sequence, 1);

    let Decoded::Event(e) = decode_frame(&capture("event_16")).unwrap() else {
        panic!()
    };
    assert_eq!((e.code, e.unix_s), (34, 1_792_780_876));

    let Decoded::Metadata(m) = decode_frame(&capture("history_start")).unwrap() else {
        panic!()
    };
    assert_eq!(m.kind, MetadataKind::HistoryStart);
    assert!(m.history_end.is_none());

    let Decoded::Other { packet_type, len } = decode_frame(&capture("console_log")).unwrap() else {
        panic!()
    };
    assert_eq!((packet_type, len), (PacketType::CONSOLE_LOGS, 76));
}
