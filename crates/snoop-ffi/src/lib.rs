//! Swift-facing API. Kept small and JSON-shaped: the iOS app forwards raw frames to
//! the server anyway, so the phone only needs enough decoding to show live numbers
//! and to drive the offload ACK loop.

use std::sync::Mutex;

uniffi::setup_scaffolding!();

const CURSOR_LEN: usize = 8;

/// The fixed CLIENT_HELLO frame to write to fd4b0002 after subscribing.
#[uniffi::export]
pub fn client_hello() -> Vec<u8> {
    snoop_proto::CLIENT_HELLO.to_vec()
}

/// Builds the 0x17 ACK echoing the 8-byte cursor found at inner offset 13 of a
/// progress status frame. Shorter cursors are zero-padded, longer ones truncated.
#[uniffi::export]
pub fn history_ack(seq: u8, cursor: Vec<u8>) -> Vec<u8> {
    let mut fixed = [0u8; CURSOR_LEN];
    let n = cursor.len().min(CURSOR_LEN);
    fixed[..n].copy_from_slice(&cursor[..n]);
    snoop_proto::history_ack(seq, &fixed)
}

/// Reassembles BLE notification fragments into complete frames.
#[derive(Debug, uniffi::Object)]
pub struct FrameReassembler {
    inner: Mutex<snoop_proto::Reassembler>,
}

#[uniffi::export]
impl FrameReassembler {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(snoop_proto::Reassembler::new(
                snoop_proto::DeviceFamily::Whoop5,
            )),
        }
    }

    /// Feeds one notification; returns zero or more complete frames.
    pub fn feed(&self, fragment: Vec<u8>) -> Vec<Vec<u8>> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .feed(&fragment)
    }
}

impl Default for FrameReassembler {
    fn default() -> Self {
        Self::new()
    }
}

/// Decodes one complete frame to JSON (see `snoop_proto::Decoded`).
///
/// # Errors
///
/// The envelope fails its CRC checks.
#[uniffi::export]
pub fn decode_frame_json(frame: Vec<u8>) -> Result<String, FfiError> {
    let decoded = snoop_proto::decode_frame(&frame).map_err(|error| FfiError::Decode {
        message: error.to_string(),
    })?;
    serde_json::to_string(&decoded).map_err(|error| FfiError::Decode {
        message: error.to_string(),
    })
}

/// RMSSD in ms over a window of R-R intervals, after cleaning.
#[uniffi::export]
pub fn rmssd_ms(rr_ms: Vec<u32>) -> Option<f64> {
    let cleaned = snoop_analytics::hrv::clean_rr(&rr_ms);
    snoop_analytics::hrv::rmssd(&cleaned)
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum FfiError {
    #[error("decode: {message}")]
    Decode { message: String },
}
