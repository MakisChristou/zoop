//! WHOOP 5.0 / MG Bluetooth protocol, written from scratch for snoop.
//!
//! The strap speaks a "format-1" envelope over the `fd4b…` GATT service: a fixed
//! 8-byte header with a CRC-16/MODBUS check, an inner packet, and a CRC-32 trailer.
//! This crate validates and reassembles those frames, decodes the records that
//! matter for sleep (R18 biometric summary), ECG strips (R16/R17 on the MG), events,
//! metadata and command responses, and builds the commands the phone must send.
//!
//! Byte layouts come from public interoperability research (NOOP, wearable5.0,
//! Goose, whoop-rs); none of their code is used.

mod command;
mod crc;
mod decode;
mod error;
mod event;
mod framing;
pub mod gatt;
mod record;
mod response;

pub use command::{
    CLIENT_HELLO, Command, build_command, get_data_range, history_ack, send_historical_data,
};
pub use crc::{crc16_modbus, crc32};
pub use decode::{Decoded, PROTO_VERSION, decode_frame};
pub use error::{ProtoError, ProtoResult};
pub use event::{BatteryLevel, Event, EventPayload};
pub use framing::{Frame, HEADER_LEN, MIN_FRAME_LEN, PacketType, Reassembler, TRAILER_LEN};
pub use record::{
    ActivityClass, BandState, Biometric, EcgStrip, Layout, RecordHeader, UnknownRecord,
};
pub use response::{
    CommandResponse, DataRange, HistoryEnd, Metadata, MetadataKind, RealtimeHr, ResultCode,
};
