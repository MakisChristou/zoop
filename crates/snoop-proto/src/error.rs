#[derive(Debug, thiserror::Error)]
pub enum DecodeError {
    #[error("frame failed envelope check: {reason}")]
    BadFrame { reason: String },
    #[error("frame has no packet type byte")]
    NoPacketType,
}

pub type DecodeResult<T> = Result<T, DecodeError>;
