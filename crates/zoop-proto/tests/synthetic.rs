//! Round-trip tests on frames built by our own encoder. Real captures from a strap
//! are added as fixtures once available; these guard the byte offsets meanwhile.

use zoop_proto::{
    ActivityClass, BandState, Biometric, Decoded, Event, EventPayload, Layout, MetadataKind,
    PacketType, Reassembler, RecordHeader, ResultCode, crc16_modbus, crc32, decode_frame,
};

/// Wraps an inner packet exactly the way the strap does.
fn envelope(inner: &[u8]) -> Vec<u8> {
    let mut body = inner.to_vec();
    while !body.len().is_multiple_of(4) {
        body.push(0);
    }
    let declared = (body.len() + 4) as u16;
    let mut frame = vec![0xAA, 0x01];
    frame.extend_from_slice(&declared.to_le_bytes());
    frame.extend_from_slice(&[0x01, 0x00]); // strap -> phone
    let crc = crc16_modbus(&frame);
    frame.extend_from_slice(&crc.to_le_bytes());
    frame.extend_from_slice(&body);
    frame.extend_from_slice(&crc32(&body).to_le_bytes());
    frame
}

fn put_u16(buf: &mut [u8], offset: usize, value: u16) {
    buf[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}
fn put_u32(buf: &mut [u8], offset: usize, value: u32) {
    buf[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}
fn put_f32(buf: &mut [u8], offset: usize, value: f32) {
    buf[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

struct R18 {
    unix_s: u32,
    hr: u8,
    rr_ms: Vec<u16>,
    skin_temp_c: f32,
    steps: u16,
    band_state: BandState,
    spo2: u8,
    gravity: [f32; 3],
}

/// Builds a 124-byte R18 frame. Offsets are frame-absolute, matching the decoder.
fn r18_frame(r: &R18) -> Vec<u8> {
    let mut f = vec![0u8; 124];
    f[8] = PacketType::HISTORICAL_DATA;
    f[9] = Layout::BIOMETRIC;
    f[10] = 0x80;
    put_u32(&mut f, 11, 4242);
    put_u32(&mut f, 15, r.unix_s);
    put_u16(&mut f, 19, 0);
    f[Biometric::HR_OFFSET] = r.hr;
    f[Biometric::RR_COUNT_OFFSET] = r.rr_ms.len() as u8;
    for (i, rr) in r.rr_ms.iter().enumerate() {
        put_u16(&mut f, Biometric::RR_OFFSET + i * 2, *rr);
    }
    put_f32(&mut f, Biometric::DYN_ACCEL_OFFSET, 0.02);
    for (i, g) in r.gravity.iter().enumerate() {
        put_f32(&mut f, Biometric::GRAVITY_OFFSET + i * 4, *g);
    }
    put_u16(&mut f, Biometric::STEPS_OFFSET, r.steps);
    f[Biometric::ACTIVITY_OFFSET] = 0;
    put_u16(&mut f, Biometric::TEMP_AUX1_OFFSET, 331);
    put_u16(
        &mut f,
        Biometric::SKIN_TEMP_OFFSET,
        (r.skin_temp_c * 100.0).round() as u16,
    );
    f[Biometric::STATE_BITS_OFFSET] = r.band_state.to_state_bits();
    f[Biometric::SPO2_OFFSET] = r.spo2;
    // Header and trailer over the body we just filled.
    let inner = f[8..120].to_vec();
    let mut frame = envelope(&inner);
    assert_eq!(frame.len(), 124);
    frame.truncate(124);
    frame
}

#[test]
fn r18_roundtrip_decodes_every_field_we_rely_on() {
    let frame = r18_frame(&R18 {
        unix_s: 1_790_000_000,
        hr: 52,
        rr_ms: vec![1150, 1160, 0, 0],
        skin_temp_c: 34.12,
        steps: 1234,
        band_state: BandState::Sleep,
        spo2: 97,
        gravity: [0.1, -0.2, 0.97],
    });
    let Decoded::Biometric(b) = decode_frame(&frame).unwrap() else {
        panic!("expected a biometric record");
    };
    assert_eq!(b.header.layout, Layout::Biometric);
    assert_eq!(b.header.record_index, 4242);
    assert_eq!(b.header.unix_s, 1_790_000_000);
    assert_eq!(b.heart_rate, 52);
    assert_eq!(
        b.rr_ms,
        vec![1150, 1160],
        "zero placeholders dropped, units are ms"
    );
    assert_eq!(b.steps, 1234);
    assert_eq!(b.activity, ActivityClass::Still);
    assert!((b.skin_temp_c.unwrap() - 34.12).abs() < 0.005);
    assert!((b.temp_aux1_c.unwrap() - 33.1).abs() < 0.05);
    assert_eq!(b.band_state, BandState::Sleep);
    assert_eq!(b.spo2_percent, Some(97));
    assert_eq!(b.gravity_g, Some([0.1, -0.2, 0.97]));
}

#[test]
fn r18_band_states_and_spo2_status_codes() {
    for (state, bits) in [
        (BandState::Wake, 0x00),
        (BandState::Still, 0x10),
        (BandState::Sleep, 0x20),
        (BandState::Up, 0x30),
    ] {
        assert_eq!(BandState::from_state_bits(bits), state);
        assert_eq!(
            BandState::from_state_bits(bits | 0x0F),
            state,
            "low bits ignored"
        );
    }
    let frame = r18_frame(&R18 {
        unix_s: 1,
        hr: 60,
        rr_ms: vec![],
        skin_temp_c: 33.0,
        steps: 0,
        band_state: BandState::Wake,
        spo2: 160, // status code, not a percentage
        gravity: [0.0, 0.0, 1.0],
    });
    let Decoded::Biometric(b) = decode_frame(&frame).unwrap() else {
        panic!()
    };
    assert_eq!(b.spo2_percent, None);
    assert_eq!(b.spo2_raw, 160);
    assert!(b.rr_ms.is_empty());
}

#[test]
fn r18_with_wrong_length_is_rejected_not_misread() {
    let mut inner = vec![0u8; 100];
    inner[0] = PacketType::HISTORICAL_DATA;
    inner[1] = Layout::BIOMETRIC;
    let frame = envelope(&inner);
    assert!(decode_frame(&frame).is_err());
}

#[test]
fn history_end_token_is_extracted_verbatim() {
    let mut inner = vec![0u8; 24];
    inner[0] = PacketType::METADATA;
    inner[2] = 2; // HISTORY_END
    put_u32(&mut inner, 3, 1_790_000_100);
    inner[13..21].copy_from_slice(&[9, 8, 7, 6, 5, 4, 3, 2]);
    let Decoded::Metadata(m) = decode_frame(&envelope(&inner)).unwrap() else {
        panic!()
    };
    assert_eq!(m.kind, MetadataKind::HistoryEnd);
    assert_eq!(m.unix_s, 1_790_000_100);
    let end = m.history_end.unwrap();
    assert_eq!(end.token, [9, 8, 7, 6, 5, 4, 3, 2]);
    assert_eq!(end.trim_cursor(), u32::from_le_bytes([9, 8, 7, 6]));

    // Echo it back as an ACK and check the wire bytes.
    let ack = zoop_proto::history_ack(3, &end.token).unwrap();
    assert_eq!(&ack[8..20], &[35, 3, 23, 1, 9, 8, 7, 6, 5, 4, 3, 2]);
}

#[test]
fn battery_event_payload_decodes() {
    let mut inner = vec![0u8; 20];
    inner[0] = PacketType::EVENT;
    inner[2] = Event::BATTERY_LEVEL;
    put_u32(&mut inner, 4, 1_790_000_200);
    put_u16(&mut inner, 10, 7); // payload length
    inner[12] = 1; // revision
    put_u16(&mut inner, 13, 873); // 87.3 %
    put_u16(&mut inner, 17, 4120); // mV
    let Decoded::Event(e) = decode_frame(&envelope(&inner)).unwrap() else {
        panic!()
    };
    assert_eq!(e.code, Event::BATTERY_LEVEL);
    assert_eq!(e.unix_s, 1_790_000_200);
    let EventPayload::BatteryLevel(b) = e.payload else {
        panic!()
    };
    assert_eq!((b.soc_tenths, b.millivolts), (873, 4120));
}

#[test]
fn realtime_hr_decodes_rr_in_ms() {
    let mut inner = vec![0u8; 16];
    inner[0] = PacketType::REALTIME_DATA;
    put_u32(&mut inner, 2, 1_790_000_300);
    inner[8] = 61;
    inner[9] = 2;
    put_u16(&mut inner, 10, 980);
    put_u16(&mut inner, 12, 990);
    let Decoded::RealtimeHr(hr) = decode_frame(&envelope(&inner)).unwrap() else {
        panic!()
    };
    assert_eq!(hr.heart_rate, 61);
    assert_eq!(hr.rr_ms, vec![980, 990]);
}

#[test]
fn command_response_and_data_range() {
    let mut inner = vec![0u8; 5 + 65];
    inner[0] = PacketType::COMMAND_RESPONSE;
    inner[1] = 7;
    inner[2] = 34; // GET_DATA_RANGE
    inner[3] = 7;
    inner[4] = 1; // success
    let body = &mut inner[5..];
    body[0] = 1;
    put_u32(body, 9, 120); // write_page
    put_u32(body, 13, 100); // trim_page
    put_u32(body, 21, 1000); // total_pages
    put_u32(body, 57, 1_790_000_400); // newest clock
    let Decoded::CommandResponse(r) = decode_frame(&envelope(&inner)).unwrap() else {
        panic!()
    };
    assert_eq!(r.result, ResultCode::Success);
    let range = r.data_range.unwrap();
    assert_eq!(range.pages_behind(), Some(20));
    assert_eq!(range.newest_clock_s, Some(1_790_000_400));
}

#[test]
fn unknown_layout_is_preserved_not_rejected() {
    let mut inner = vec![0u8; 40];
    inner[0] = PacketType::HISTORICAL_DATA;
    inner[1] = Layout::V9_CHANNELS;
    let Decoded::UnknownRecord(u) = decode_frame(&envelope(&inner)).unwrap() else {
        panic!()
    };
    assert_eq!(u.header.layout, Layout::V9);
    assert_eq!(u.frame_len, 52);
    let header: RecordHeader = u.header;
    assert_eq!(header.marker, 0);
}

#[test]
fn reassembler_recovers_a_record_split_across_notifications() {
    let frame = r18_frame(&R18 {
        unix_s: 5,
        hr: 70,
        rr_ms: vec![857],
        skin_temp_c: 32.5,
        steps: 9,
        band_state: BandState::Up,
        spo2: 0,
        gravity: [0.0, 0.0, 1.0],
    });
    let mut r = Reassembler::new();
    let mut out = Vec::new();
    for chunk in frame.chunks(20) {
        out.extend(r.feed(chunk));
    }
    assert_eq!(out, vec![frame]);
}
