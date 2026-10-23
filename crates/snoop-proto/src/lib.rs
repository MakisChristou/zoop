//! Thin, stable facade over the `poop` crate (eugenehp/whoop-rs, Apache-2.0).
//!
//! Everything that touches WHOOP bytes goes through here so the iOS app (via
//! `snoop-ffi`) and the backend decode identically. The MG is the target device;
//! WHOOP 4.0 paths are not exposed.

mod decode;
mod error;
pub mod gatt;

pub use decode::{CLIENT_HELLO, Decoded, PROTO_VERSION, decode_frame, history_ack};
pub use error::{DecodeError, DecodeResult};
pub use poop::protocol::{DeviceFamily, Reassembler};
pub use poop::types::{
    BiometricRecord, CompactOpticalRecord, EcgRecord, ImuRecord, OpticalRecord, Record,
};
