use poop::protocol::{DeviceFamily, packet_type, verify_frame, whoop5_frame_with};
use serde::Serialize;

use crate::{BiometricRecord, DecodeError, DecodeResult, Record};

/// Bump whenever decoding output changes shape or meaning. Stored next to every
/// decoded row so the worker can re-decode history after a protocol fix.
pub const PROTO_VERSION: i32 = 1;

/// Fixed CLIENT_HELLO frame for WHOOP 5/MG (GET_HELLO, b3 = 0x01), byte-exact to
/// hardware captures documented by NOOP and wearable5.0.
pub const CLIENT_HELLO: [u8; 16] = [
    0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
];

const PACKET_TYPE_LIVE_RECORD: u8 = 43;
const PACKET_TYPE_HISTORICAL_RECORD: u8 = 47;
const CMD_HISTORY_ACK: u8 = 0x17;
const PACKET_TYPE_COMMAND: u8 = 0x23;

/// One complete, CRC-valid WHOOP 5/MG frame, classified.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Decoded {
    /// Packet types 43/47: a stored or live sensor record.
    Record { packet_type: u8, record: Record },
    /// Any other packet type (command responses, events, console, metadata), kept
    /// so the raw store never loses anything.
    Other { packet_type: u8, len: usize },
}

/// Verifies the envelope (CRC-16/MODBUS header, CRC-32 body) and decodes one frame.
///
/// # Errors
///
/// The frame fails its checksums or carries no packet type.
pub fn decode_frame(frame: &[u8]) -> DecodeResult<Decoded> {
    let check = verify_frame(frame, DeviceFamily::Whoop5);
    if !check.ok {
        return Err(DecodeError::BadFrame {
            reason: format!("{:?}", check.reason),
        });
    }
    let packet_type = packet_type(frame, DeviceFamily::Whoop5).ok_or(DecodeError::NoPacketType)?;

    Ok(match packet_type {
        PACKET_TYPE_LIVE_RECORD | PACKET_TYPE_HISTORICAL_RECORD => {
            let mut record = poop::parse::whoop5_record(frame, packet_type);
            if let Record::Biometric(biometric) = &mut record {
                fix_r18_rr_units(frame, biometric);
            }
            Decoded::Record {
                packet_type,
                record,
            }
        }
        _ => Decoded::Other {
            packet_type,
            len: frame.len(),
        },
    })
}

/// Builds the 0x17 history ACK that echoes an 8-byte progress cursor. Without this
/// echo the offload stalls after the first chunk.
pub fn history_ack(seq: u8, cursor: &[u8; 8]) -> Vec<u8> {
    whoop5_frame_with(
        CMD_HISTORY_ACK,
        seq,
        cursor,
        PACKET_TYPE_COMMAND,
        [0x00, 0x01],
    )
}

/// R18 R-R intervals are already milliseconds on the wire. `poop` converts them as
/// 1/1024 s ticks (the Bluetooth HR-profile unit), which is ~2.3% short and would
/// bias every HRV number. Corpus evidence: wearable5.0 FINDINGS §8 and NOOP
/// #2046/#2195 (R18 values equal the strap's own 0x2A37 R-R beat for beat and sum
/// to 0.999 of wall time read as ms). Re-read the raw words here.
fn fix_r18_rr_units(frame: &[u8], record: &mut BiometricRecord) {
    const RR_COUNT_OFFSET: usize = 23;
    const RR_FIRST_OFFSET: usize = 24;
    const RR_MAX_WORDS: usize = 4;

    let Some(&count) = frame.get(RR_COUNT_OFFSET) else {
        return;
    };
    let count = usize::from(count).min(RR_MAX_WORDS);
    let mut rr_ms = Vec::with_capacity(count);
    for i in 0..count {
        let offset = RR_FIRST_OFFSET + i * 2;
        if let (Some(&lo), Some(&hi)) = (frame.get(offset), frame.get(offset + 1)) {
            let ms = u16::from_le_bytes([lo, hi]);
            if ms != 0 {
                rr_ms.push(u32::from(ms));
            }
        }
    }
    record.heart_rate.rr_ms = rr_ms;
}
