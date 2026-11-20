//! Prints a synthetic R18 frame as hex, for exercising ingest without a strap:
//!
//! ```sh
//! cargo run -q -p zoop-proto --example synth_r18 -- 58 1790000000 | xxd -r -p | base64
//! ```
//! Arguments: heart rate (bpm) and unix seconds; both optional.

use zoop_proto::{BandState, Biometric, Layout, PacketType, crc16_modbus, crc32};

fn main() {
    let mut args = std::env::args().skip(1);
    let hr: u8 = args.next().and_then(|a| a.parse().ok()).unwrap_or(58);
    let unix_s: u32 = args
        .next()
        .and_then(|a| a.parse().ok())
        .unwrap_or(1_790_000_000);

    let mut frame = vec![0u8; 124];
    frame[8] = PacketType::HISTORICAL_DATA;
    frame[9] = Layout::BIOMETRIC;
    frame[11..15].copy_from_slice(&7u32.to_le_bytes());
    frame[15..19].copy_from_slice(&unix_s.to_le_bytes());
    frame[Biometric::HR_OFFSET] = hr;
    frame[Biometric::RR_COUNT_OFFSET] = 2;
    let rr = 60_000 / u16::from(hr);
    frame[Biometric::RR_OFFSET..Biometric::RR_OFFSET + 2].copy_from_slice(&rr.to_le_bytes());
    frame[Biometric::RR_OFFSET + 2..Biometric::RR_OFFSET + 4]
        .copy_from_slice(&(rr + 12).to_le_bytes());
    frame[Biometric::GRAVITY_OFFSET + 8..Biometric::GRAVITY_OFFSET + 12]
        .copy_from_slice(&1.0f32.to_le_bytes());
    frame[Biometric::STEPS_OFFSET..Biometric::STEPS_OFFSET + 2]
        .copy_from_slice(&1234u16.to_le_bytes());
    frame[Biometric::SKIN_TEMP_OFFSET..Biometric::SKIN_TEMP_OFFSET + 2]
        .copy_from_slice(&3412u16.to_le_bytes());
    frame[Biometric::STATE_BITS_OFFSET] = BandState::Sleep.to_state_bits();
    frame[Biometric::SPO2_OFFSET] = 97;

    frame[0] = 0xAA;
    frame[1] = 0x01;
    frame[2..4].copy_from_slice(&116u16.to_le_bytes());
    frame[4] = 0x01;
    frame[5] = 0x00;
    let header_crc = crc16_modbus(&frame[..6]);
    frame[6..8].copy_from_slice(&header_crc.to_le_bytes());
    let body_crc = crc32(&frame[8..120]);
    frame[120..124].copy_from_slice(&body_crc.to_le_bytes());

    zoop_proto::decode_frame(&frame).expect("synthetic frame decodes");
    println!(
        "{}",
        frame.iter().map(|b| format!("{b:02x}")).collect::<String>()
    );
}
