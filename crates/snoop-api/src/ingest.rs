//! Raw frame intake. The phone batches CRC-valid frames; the server re-verifies and
//! stores them. Duplicates (retries after a dropped response) are counted, not errors.

use axum::{Json, extract::State};
use base64::Engine;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use snoop_storage::NewRawFrame;

use crate::{AppState, error::ApiError};

#[derive(Debug, Deserialize)]
pub(crate) struct IngestRequest {
    pub device_id: String,
    pub model: String,
    pub firmware: Option<String>,
    pub frames: Vec<FrameUpload>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct FrameUpload {
    pub client_seq: i64,
    pub channel: i16,
    pub received_at: DateTime<Utc>,
    /// Base64 of one complete frame.
    pub bytes: String,
}

#[derive(Debug, Default, Serialize, PartialEq, Eq)]
pub(crate) struct IngestResponse {
    pub accepted: usize,
    pub duplicates: usize,
    pub rejected: usize,
}

pub(crate) async fn ingest(
    State(state): State<AppState>,
    Json(request): Json<IngestRequest>,
) -> Result<Json<IngestResponse>, ApiError> {
    if request.device_id.is_empty() {
        return Err(ApiError::BadRequest("device_id is empty".to_owned()));
    }
    state
        .store
        .upsert_device(
            &request.device_id,
            &request.model,
            request.firmware.as_deref(),
        )
        .await?;

    let base64 = base64::engine::general_purpose::STANDARD;
    let mut response = IngestResponse::default();

    for upload in &request.frames {
        let Ok(bytes) = base64.decode(&upload.bytes) else {
            response.rejected += 1;
            continue;
        };
        if snoop_proto::decode_frame(&bytes).is_err() {
            response.rejected += 1;
            continue;
        }
        let inserted = state
            .store
            .insert_raw_frame(&NewRawFrame {
                device_id: &request.device_id,
                client_seq: upload.client_seq,
                channel: upload.channel,
                received_at: upload.received_at,
                bytes: &bytes,
            })
            .await?;
        if inserted {
            response.accepted += 1;
        } else {
            response.duplicates += 1;
        }
    }

    Ok(Json(response))
}
