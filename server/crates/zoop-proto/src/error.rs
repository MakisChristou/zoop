#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ProtoError {
    #[error("frame too short: {len} bytes")]
    TooShort { len: usize },
    #[error("inner packet exceeds the wire length limit: {len} bytes")]
    TooLarge { len: usize },
    #[error("not a format-1 frame (start {start:#04x}, format {format:#04x})")]
    NotFormat1 { start: u8, format: u8 },
    #[error("declared length {declared} does not match frame length {actual}")]
    LengthMismatch { declared: usize, actual: usize },
    #[error("inner packet is not 4-byte aligned")]
    Unaligned,
    #[error("header CRC-16 mismatch")]
    HeaderCrc,
    #[error("body CRC-32 mismatch")]
    BodyCrc,
    #[error("record layout {layout} expects {expected} bytes, frame has {actual}")]
    RecordLength {
        layout: u8,
        expected: usize,
        actual: usize,
    },
    #[error("field at offset {offset} is outside the frame")]
    OutOfBounds { offset: usize },
    #[error("history end token must be 8 bytes, got {len}")]
    BadToken { len: usize },
}

pub type ProtoResult<T> = Result<T, ProtoError>;
