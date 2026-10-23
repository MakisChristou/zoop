//! Strap events, packet type 48.
//!
//! ```text
//! [10] u8      event code
//! [12] u32 LE  unix seconds
//! [16] u16 LE  sub-second
//! [18] u16 LE  payload length
//! [20] ...     payload
//! ```

use crate::{Frame, ProtoResult};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Event {
    pub code: u8,
    pub unix_s: u32,
    pub subsec: u16,
    pub payload: EventPayload,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EventPayload {
    BatteryLevel(BatteryLevel),
    Raw { bytes: Vec<u8> },
}

/// Payload of event code 3.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct BatteryLevel {
    pub revision: u8,
    /// State of charge in tenths of a percent.
    pub soc_tenths: u16,
    pub millivolts: u16,
}

impl Event {
    pub const BATTERY_LEVEL: u8 = 3;

    const CODE_OFFSET: usize = 10;
    const UNIX_OFFSET: usize = 12;
    const SUBSEC_OFFSET: usize = 16;
    const PAYLOAD_LEN_OFFSET: usize = 18;
    const PAYLOAD_OFFSET: usize = 20;

    pub(crate) fn parse(frame: &Frame<'_>) -> ProtoResult<Self> {
        let code = frame.u8_at(Self::CODE_OFFSET)?;
        let declared = usize::from(frame.u16_at(Self::PAYLOAD_LEN_OFFSET)?);
        let inner_end = frame.raw().len() - crate::TRAILER_LEN;
        let available = inner_end.saturating_sub(Self::PAYLOAD_OFFSET);
        let bytes = frame.inner_bytes(Self::PAYLOAD_OFFSET, declared.min(available))?;

        let payload = match code {
            Self::BATTERY_LEVEL if bytes.len() >= 7 => EventPayload::BatteryLevel(BatteryLevel {
                revision: bytes[0],
                soc_tenths: u16::from_le_bytes([bytes[1], bytes[2]]),
                millivolts: u16::from_le_bytes([bytes[5], bytes[6]]),
            }),
            _ => EventPayload::Raw {
                bytes: bytes.to_vec(),
            },
        };

        Ok(Self {
            code,
            unix_s: frame.u32_at(Self::UNIX_OFFSET)?,
            subsec: frame.u16_at(Self::SUBSEC_OFFSET)?,
            payload,
        })
    }
}
