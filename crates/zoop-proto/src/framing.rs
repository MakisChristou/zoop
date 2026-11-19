//! Format-1 envelope.
//!
//! ```text
//! [0]  0xAA            start of frame
//! [1]  0x01            format 1
//! [2]  u16 LE          declared length = frame length - 8
//! [4]  u8              destination (requests 0x00, strap replies 0x01)
//! [5]  u8              source      (requests 0x01, strap replies 0x00)
//! [6]  u16 LE          CRC-16/MODBUS over bytes [0, 6)
//! [8]  ...             inner packet: [type][seq][...], zero-padded to a multiple of 4
//! [-4] u32 LE          CRC-32 over the inner packet
//! ```

use crate::{ProtoError, ProtoResult, crc16_modbus, crc32};

pub const START_OF_FRAME: u8 = 0xAA;
pub const FORMAT1: u8 = 0x01;
pub const HEADER_LEN: usize = 8;
pub const TRAILER_LEN: usize = 4;
/// Smallest valid frame: header, a 4-byte inner packet, trailer.
pub const MIN_FRAME_LEN: usize = HEADER_LEN + 4 + TRAILER_LEN;
/// Largest record seen on the wire is R20 at 2,140 bytes; anything far above is noise.
pub const MAX_FRAME_LEN: usize = 4096;

const DECLARED_LEN_OFFSET: usize = 2;
const HEADER_CRC_OFFSET: usize = 6;
const PACKET_TYPE_OFFSET: usize = HEADER_LEN;

/// Inner packet types (first inner byte).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum PacketType {
    Command,
    CommandResponse,
    RealtimeData,
    RealtimeRawData,
    HistoricalData,
    Event,
    Metadata,
    ConsoleLogs,
    RealtimeImuStream,
    HistoricalImuStream,
    Unknown(u8),
}

impl PacketType {
    pub const COMMAND: u8 = 35;
    pub const COMMAND_RESPONSE: u8 = 36;
    pub const REALTIME_DATA: u8 = 40;
    pub const REALTIME_RAW_DATA: u8 = 43;
    pub const HISTORICAL_DATA: u8 = 47;
    pub const EVENT: u8 = 48;
    pub const METADATA: u8 = 49;
    pub const CONSOLE_LOGS: u8 = 50;
    pub const REALTIME_IMU_STREAM: u8 = 51;
    pub const HISTORICAL_IMU_STREAM: u8 = 52;

    pub const fn from_byte(byte: u8) -> Self {
        match byte {
            Self::COMMAND => Self::Command,
            Self::COMMAND_RESPONSE => Self::CommandResponse,
            Self::REALTIME_DATA => Self::RealtimeData,
            Self::REALTIME_RAW_DATA => Self::RealtimeRawData,
            Self::HISTORICAL_DATA => Self::HistoricalData,
            Self::EVENT => Self::Event,
            Self::METADATA => Self::Metadata,
            Self::CONSOLE_LOGS => Self::ConsoleLogs,
            Self::REALTIME_IMU_STREAM => Self::RealtimeImuStream,
            Self::HISTORICAL_IMU_STREAM => Self::HistoricalImuStream,
            other => Self::Unknown(other),
        }
    }

    /// Record-carrying packets (live type 43, stored type 47) share the record header.
    pub const fn carries_record(self) -> bool {
        matches!(self, Self::RealtimeRawData | Self::HistoricalData)
    }
}

/// One complete, CRC-valid format-1 frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame<'a> {
    raw: &'a [u8],
}

impl<'a> Frame<'a> {
    /// Validates structure and both checksums.
    ///
    /// # Errors
    ///
    /// The bytes are not one complete, well-formed, checksum-valid frame.
    pub fn parse(raw: &'a [u8]) -> ProtoResult<Self> {
        if raw.len() < MIN_FRAME_LEN {
            return Err(ProtoError::TooShort { len: raw.len() });
        }
        if raw[0] != START_OF_FRAME || raw[1] != FORMAT1 {
            return Err(ProtoError::NotFormat1 {
                start: raw[0],
                format: raw[1],
            });
        }
        let declared = usize::from(u16::from_le_bytes([raw[2], raw[3]]));
        if declared + HEADER_LEN != raw.len() {
            return Err(ProtoError::LengthMismatch {
                declared: declared + HEADER_LEN,
                actual: raw.len(),
            });
        }
        if !(declared - TRAILER_LEN).is_multiple_of(4) {
            return Err(ProtoError::Unaligned);
        }
        let header_crc = u16::from_le_bytes([raw[6], raw[7]]);
        if crc16_modbus(&raw[..HEADER_CRC_OFFSET]) != header_crc {
            return Err(ProtoError::HeaderCrc);
        }
        let trailer = raw.len() - TRAILER_LEN;
        let body_crc = u32::from_le_bytes([
            raw[trailer],
            raw[trailer + 1],
            raw[trailer + 2],
            raw[trailer + 3],
        ]);
        if crc32(&raw[HEADER_LEN..trailer]) != body_crc {
            return Err(ProtoError::BodyCrc);
        }
        Ok(Self { raw })
    }

    pub const fn raw(&self) -> &'a [u8] {
        self.raw
    }

    pub fn packet_type(&self) -> PacketType {
        PacketType::from_byte(self.raw[PACKET_TYPE_OFFSET])
    }

    /// The inner packet: bytes the CRC-32 covers.
    pub fn inner(&self) -> &'a [u8] {
        &self.raw[HEADER_LEN..self.raw.len() - TRAILER_LEN]
    }

    pub(crate) fn u8_at(&self, offset: usize) -> ProtoResult<u8> {
        self.inner_bytes(offset, 1).map(|b| b[0])
    }

    pub(crate) fn u16_at(&self, offset: usize) -> ProtoResult<u16> {
        self.inner_bytes(offset, 2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]))
    }

    pub(crate) fn i16_at(&self, offset: usize) -> ProtoResult<i16> {
        self.inner_bytes(offset, 2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]))
    }

    pub(crate) fn u32_at(&self, offset: usize) -> ProtoResult<u32> {
        self.inner_bytes(offset, 4)
            .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    pub(crate) fn f32_at(&self, offset: usize) -> ProtoResult<f32> {
        self.inner_bytes(offset, 4)
            .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    /// `len` bytes at absolute frame `offset`, never reaching into the trailer.
    pub(crate) fn inner_bytes(&self, offset: usize, len: usize) -> ProtoResult<&'a [u8]> {
        let end = offset + len;
        if offset < HEADER_LEN || end > self.raw.len() - TRAILER_LEN {
            return Err(ProtoError::OutOfBounds { offset });
        }
        Ok(&self.raw[offset..end])
    }
}

/// Wraps an inner packet in a format-1 envelope.
pub fn encode_frame(inner: &[u8], destination: u8, source: u8) -> Vec<u8> {
    let padding = (4 - inner.len() % 4) % 4;
    let mut body = Vec::with_capacity(inner.len() + padding);
    body.extend_from_slice(inner);
    body.resize(inner.len() + padding, 0);

    let declared = u16::try_from(body.len() + TRAILER_LEN).expect("frames are far below u16::MAX");
    let mut frame = Vec::with_capacity(HEADER_LEN + body.len() + TRAILER_LEN);
    frame.extend_from_slice(&[START_OF_FRAME, FORMAT1]);
    frame.extend_from_slice(&declared.to_le_bytes());
    frame.extend_from_slice(&[destination, source]);
    let header_crc = crc16_modbus(&frame);
    frame.extend_from_slice(&header_crc.to_le_bytes());
    frame.extend_from_slice(&body);
    frame.extend_from_slice(&crc32(&body).to_le_bytes());
    frame
}

/// Joins BLE notification fragments into complete frames.
///
/// Records up to 2,140 bytes arrive across many notifications; only the first
/// fragment starts with the frame marker. Bytes that cannot start a valid frame
/// are skipped one at a time, so a corrupt fragment costs at most one frame.
#[derive(Debug, Default)]
pub struct Reassembler {
    buffer: Vec<u8>,
    dropped_bytes: u64,
}

impl Reassembler {
    pub fn new() -> Self {
        Self::default()
    }

    /// Bytes discarded while hunting for a valid frame start.
    pub const fn dropped_bytes(&self) -> u64 {
        self.dropped_bytes
    }

    pub fn pending_bytes(&self) -> usize {
        self.buffer.len()
    }

    /// Feeds one notification; returns every complete frame now available.
    pub fn feed(&mut self, fragment: &[u8]) -> Vec<Vec<u8>> {
        self.buffer.extend_from_slice(fragment);
        let mut frames = Vec::new();
        loop {
            let Some(start) = self.find_start() else {
                // Keep a trailing 0xAA: it may be the first byte of the next frame.
                let keep = usize::from(self.buffer.last() == Some(&START_OF_FRAME));
                self.dropped_bytes += (self.buffer.len() - keep) as u64;
                self.buffer.drain(..self.buffer.len() - keep);
                break;
            };
            if start > 0 {
                self.dropped_bytes += start as u64;
                self.buffer.drain(..start);
            }
            if self.buffer.len() < DECLARED_LEN_OFFSET + 2 {
                break;
            }
            let total =
                usize::from(u16::from_le_bytes([self.buffer[2], self.buffer[3]])) + HEADER_LEN;
            if !(MIN_FRAME_LEN..=MAX_FRAME_LEN).contains(&total) {
                self.skip_one();
                continue;
            }
            if self.buffer.len() < total {
                break;
            }
            if Frame::parse(&self.buffer[..total]).is_err() {
                self.skip_one();
                continue;
            }
            frames.push(self.buffer.drain(..total).collect());
        }
        frames
    }

    fn find_start(&self) -> Option<usize> {
        self.buffer
            .windows(2)
            .position(|pair| pair == [START_OF_FRAME, FORMAT1])
    }

    fn skip_one(&mut self) {
        self.buffer.remove(0);
        self.dropped_bytes += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn command(inner: &[u8]) -> Vec<u8> {
        encode_frame(inner, 0x00, 0x01)
    }

    #[test]
    fn encode_then_parse_roundtrips() {
        let frame = command(&[PacketType::COMMAND, 7, 0x91, 0x01]);
        let parsed = Frame::parse(&frame).unwrap();
        assert_eq!(parsed.packet_type(), PacketType::Command);
        assert_eq!(parsed.inner(), &[PacketType::COMMAND, 7, 0x91, 0x01]);
    }

    #[test]
    fn encode_pads_inner_to_four_bytes() {
        let frame = command(&[PacketType::COMMAND, 0, 0x17, 0x01, 1, 2, 3, 4, 5, 6, 7, 8]);
        assert_eq!(frame.len(), HEADER_LEN + 12 + TRAILER_LEN);
        let frame = command(&[PacketType::COMMAND, 0, 0x22]);
        assert_eq!(frame.len(), HEADER_LEN + 4 + TRAILER_LEN);
        assert_eq!(
            Frame::parse(&frame).unwrap().inner(),
            &[PacketType::COMMAND, 0, 0x22, 0]
        );
    }

    #[test]
    fn corrupt_checksums_are_rejected() {
        let mut frame = command(&[PacketType::COMMAND, 0, 0x91, 0x01]);
        frame[7] ^= 0xFF;
        assert_eq!(Frame::parse(&frame), Err(ProtoError::HeaderCrc));

        let mut frame = command(&[PacketType::COMMAND, 0, 0x91, 0x01]);
        frame[9] ^= 0x01;
        assert_eq!(Frame::parse(&frame), Err(ProtoError::BodyCrc));
    }

    #[test]
    fn reassembler_joins_fragments_and_skips_noise() {
        let a = command(&[PacketType::EVENT, 1, 3, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
        let b = command(&[PacketType::COMMAND_RESPONSE, 2, 0x91, 1, 1, 0, 0, 0]);
        let mut stream = vec![0x00, 0xAA, 0x55]; // noise, including a fake start byte
        stream.extend_from_slice(&a);
        stream.extend_from_slice(&b);

        let mut reassembler = Reassembler::new();
        let mut frames = Vec::new();
        for chunk in stream.chunks(5) {
            frames.extend(reassembler.feed(chunk));
        }
        assert_eq!(frames, vec![a, b]);
        assert_eq!(reassembler.pending_bytes(), 0);
        assert_eq!(reassembler.dropped_bytes(), 3);
    }
}
