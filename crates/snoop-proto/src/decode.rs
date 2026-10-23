use serde::Serialize;

use crate::{
    Biometric, CommandResponse, EcgStrip, Event, Frame, Layout, Metadata, PacketType, ProtoError,
    ProtoResult, RealtimeHr, RecordHeader, UnknownRecord,
};

/// Bump whenever decoding output changes shape or meaning. Stored next to every
/// decoded row so stored raw frames can be re-decoded after a protocol fix.
pub const PROTO_VERSION: i32 = 2;

/// One complete, CRC-valid frame, decoded as far as the protocol is understood.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Decoded {
    Biometric(Biometric),
    Ecg(EcgStrip),
    UnknownRecord(UnknownRecord),
    RealtimeHr(RealtimeHr),
    Event(Event),
    Metadata(Metadata),
    CommandResponse(CommandResponse),
    /// Console logs, IMU streams and anything else: classified, kept raw.
    Other {
        packet_type: u8,
        len: usize,
    },
}

/// Validates the envelope and decodes one frame.
///
/// # Errors
///
/// The bytes are not a valid format-1 frame, or a record's fixed length does not
/// match its layout.
pub fn decode_frame(raw: &[u8]) -> ProtoResult<Decoded> {
    let frame = Frame::parse(raw)?;
    let packet_type = frame.packet_type();
    Ok(match packet_type {
        PacketType::RealtimeRawData | PacketType::HistoricalData => decode_record(&frame)?,
        PacketType::RealtimeData => Decoded::RealtimeHr(RealtimeHr::parse(&frame)?),
        PacketType::Event => Decoded::Event(Event::parse(&frame)?),
        PacketType::Metadata => Decoded::Metadata(Metadata::parse(&frame)?),
        PacketType::CommandResponse => Decoded::CommandResponse(CommandResponse::parse(&frame)?),
        other => Decoded::Other {
            packet_type: packet_type_byte(other, raw),
            len: raw.len(),
        },
    })
}

fn decode_record(frame: &Frame<'_>) -> ProtoResult<Decoded> {
    let header = RecordHeader::parse(frame)?;
    if let Some(expected) = header.layout.frame_len()
        && expected != frame.raw().len()
    {
        return Err(ProtoError::RecordLength {
            layout: header.layout.as_byte(),
            expected,
            actual: frame.raw().len(),
        });
    }
    Ok(match header.layout {
        Layout::Biometric => Decoded::Biometric(Biometric::parse(frame, header)?),
        Layout::EcgRaw | Layout::EcgFiltered => Decoded::Ecg(EcgStrip::parse(frame, header)?),
        _ => Decoded::UnknownRecord(UnknownRecord {
            header,
            frame_len: frame.raw().len(),
        }),
    })
}

fn packet_type_byte(packet_type: PacketType, raw: &[u8]) -> u8 {
    match packet_type {
        PacketType::Unknown(byte) => byte,
        _ => raw[crate::HEADER_LEN],
    }
}
