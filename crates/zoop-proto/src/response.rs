//! Replies from the strap: command responses (36), live heart rate (40) and the
//! history-offload metadata markers (49).

use crate::{Frame, ProtoError, ProtoResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum ResultCode {
    Failure,
    Success,
    Pending,
    Unsupported,
    Unknown(u8),
}

impl ResultCode {
    pub const fn from_byte(byte: u8) -> Self {
        match byte {
            0 => Self::Failure,
            1 => Self::Success,
            2 => Self::Pending,
            3 => Self::Unsupported,
            other => Self::Unknown(other),
        }
    }
}

/// Packet type 36: `[36][seq][command][origin seq][result][body…]`.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct CommandResponse {
    pub sequence: u8,
    pub command: u8,
    pub origin_sequence: u8,
    pub result: ResultCode,
    pub body: Vec<u8>,
    /// Decoded when the command was GET_DATA_RANGE and the body is complete.
    pub data_range: Option<DataRange>,
}

impl CommandResponse {
    const SEQUENCE_OFFSET: usize = 9;
    const COMMAND_OFFSET: usize = 10;
    const ORIGIN_OFFSET: usize = 11;
    const RESULT_OFFSET: usize = 12;
    pub const BODY_OFFSET: usize = 13;

    pub(crate) fn parse(frame: &Frame<'_>) -> ProtoResult<Self> {
        let inner_end = frame.raw().len() - crate::TRAILER_LEN;
        let body = frame
            .inner_bytes(
                Self::BODY_OFFSET,
                inner_end.saturating_sub(Self::BODY_OFFSET),
            )?
            .to_vec();
        let command = frame.u8_at(Self::COMMAND_OFFSET)?;
        let result = ResultCode::from_byte(frame.u8_at(Self::RESULT_OFFSET)?);
        let data_range = (command == crate::Command::GetDataRange.code()
            && result == ResultCode::Success)
            .then(|| DataRange::parse(&body))
            .flatten();

        Ok(Self {
            sequence: frame.u8_at(Self::SEQUENCE_OFFSET)?,
            command,
            origin_sequence: frame.u8_at(Self::ORIGIN_OFFSET)?,
            result,
            body,
            data_range,
        })
    }
}

/// GET_DATA_RANGE reply body: where the strap's history ring buffer stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct DataRange {
    pub revision: u8,
    pub ring_boundary: u32,
    pub read_page: u32,
    pub write_page: u32,
    pub trim_page: u32,
    pub write_wrap: u32,
    pub total_pages: u32,
    pub record_estimate: u32,
    pub newest_clock_s: Option<u32>,
}

impl DataRange {
    pub const BODY_LEN: usize = 65;
    const CLOCK_SENTINELS: [u32; 2] = [0, u32::MAX];

    fn parse(body: &[u8]) -> Option<Self> {
        if body.len() < Self::BODY_LEN {
            return None;
        }
        let u32_at = |offset: usize| {
            u32::from_le_bytes([
                body[offset],
                body[offset + 1],
                body[offset + 2],
                body[offset + 3],
            ])
        };
        let newest = u32_at(57);
        Some(Self {
            revision: body[0],
            ring_boundary: u32_at(1),
            read_page: u32_at(5),
            write_page: u32_at(9),
            trim_page: u32_at(13),
            write_wrap: u32_at(17),
            total_pages: u32_at(21),
            record_estimate: u32_at(25),
            newest_clock_s: (!Self::CLOCK_SENTINELS.contains(&newest)).then_some(newest),
        })
    }

    /// Pages written but not yet offloaded, accounting for ring wrap-around.
    pub const fn pages_behind(&self) -> Option<u32> {
        if self.total_pages == 0
            || self.write_page >= self.total_pages
            || self.trim_page >= self.total_pages
        {
            return None;
        }
        Some(if self.write_page >= self.trim_page {
            self.write_page - self.trim_page
        } else {
            (self.total_pages - self.trim_page) + self.write_page
        })
    }
}

/// Packet type 40: live heart rate with the strap's own clock.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct RealtimeHr {
    pub unix_s: u32,
    pub aux_time: u16,
    pub heart_rate: u8,
    /// R-R intervals in milliseconds, zero placeholders removed.
    pub rr_ms: Vec<u16>,
}

impl RealtimeHr {
    const UNIX_OFFSET: usize = 10;
    const AUX_TIME_OFFSET: usize = 14;
    const HR_OFFSET: usize = 16;
    const RR_COUNT_OFFSET: usize = 17;
    const RR_OFFSET: usize = 18;
    const RR_MAX: usize = 64;

    pub(crate) fn parse(frame: &Frame<'_>) -> ProtoResult<Self> {
        let count = usize::from(frame.u8_at(Self::RR_COUNT_OFFSET)?).min(Self::RR_MAX);
        let mut rr_ms = Vec::with_capacity(count);
        for i in 0..count {
            match frame.u16_at(Self::RR_OFFSET + i * 2) {
                Ok(0) => {}
                Ok(rr) => rr_ms.push(rr),
                Err(ProtoError::OutOfBounds { .. }) => break,
                Err(error) => return Err(error),
            }
        }
        Ok(Self {
            unix_s: frame.u32_at(Self::UNIX_OFFSET)?,
            aux_time: frame.u16_at(Self::AUX_TIME_OFFSET)?,
            heart_rate: frame.u8_at(Self::HR_OFFSET)?,
            rr_ms,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum MetadataKind {
    HistoryStart,
    HistoryEnd,
    HistoryComplete,
    Unknown(u8),
}

impl MetadataKind {
    pub const fn from_byte(byte: u8) -> Self {
        match byte {
            1 => Self::HistoryStart,
            2 => Self::HistoryEnd,
            3 => Self::HistoryComplete,
            other => Self::Unknown(other),
        }
    }
}

/// The 8-byte token a HISTORY_END marker carries. Echo it verbatim in the ACK or
/// the offload stalls after this chunk.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct HistoryEnd {
    pub token: [u8; 8],
}

impl HistoryEnd {
    /// The first word of the token is the trim cursor.
    pub const fn trim_cursor(&self) -> u32 {
        u32::from_le_bytes([self.token[0], self.token[1], self.token[2], self.token[3]])
    }
}

/// Packet type 49: history offload markers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct Metadata {
    pub kind: MetadataKind,
    pub unix_s: u32,
    pub subsec: u16,
    pub history_end: Option<HistoryEnd>,
}

impl Metadata {
    const KIND_OFFSET: usize = 10;
    const UNIX_OFFSET: usize = 11;
    const SUBSEC_OFFSET: usize = 15;
    pub const TOKEN_OFFSET: usize = 21;

    pub(crate) fn parse(frame: &Frame<'_>) -> ProtoResult<Self> {
        let kind = MetadataKind::from_byte(frame.u8_at(Self::KIND_OFFSET)?);
        let history_end = match kind {
            MetadataKind::HistoryEnd => {
                frame.inner_bytes(Self::TOKEN_OFFSET, 8).ok().map(|bytes| {
                    let mut token = [0u8; 8];
                    token.copy_from_slice(bytes);
                    HistoryEnd { token }
                })
            }
            _ => None,
        };
        Ok(Self {
            kind,
            unix_s: frame.u32_at(Self::UNIX_OFFSET)?,
            subsec: frame.u16_at(Self::SUBSEC_OFFSET)?,
            history_end,
        })
    }
}
