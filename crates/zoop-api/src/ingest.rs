//! Per-frame durable receipts, with a conservative compatibility route for old clients.
use crate::{AppState, error::ApiError};
use axum::{Json, extract::State};
use base64::Engine;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use zoop_storage::{IngestOutcome, NewRawFrame};

const MAX_BATCH: usize = 500;
#[derive(Debug, Deserialize)]
pub(crate) struct IngestRequest {
    device_id: String,
    model: String,
    firmware: Option<String>,
    frames: Vec<FrameUpload>,
}
#[derive(Debug, Deserialize)]
struct FrameUpload {
    client_seq: i64,
    #[serde(default)]
    upload_id: Option<String>,
    channel: i16,
    received_at: DateTime<Utc>,
    bytes: String,
}
#[derive(Debug, Default, Serialize)]
pub(crate) struct IngestResponse {
    accepted: usize,
    duplicates: usize,
    rejected: usize,
    results: Vec<Receipt>,
}
#[derive(Debug, Serialize)]
struct Receipt {
    client_seq: i64,
    upload_id: Option<String>,
    status: &'static str,
    reason: Option<&'static str>,
}

pub(crate) async fn ingest(
    State(state): State<AppState>,
    Json(request): Json<IngestRequest>,
) -> Result<Json<IngestResponse>, ApiError> {
    let result = process(&state, request, false).await?;
    // An older app deletes the ENTIRE batch on 2xx. Never acknowledge a partial batch.
    if result.rejected > 0 {
        return Err(ApiError::BadRequest(
            "batch contains unacknowledged frames; retain and upgrade the uploader".into(),
        ));
    }
    Ok(Json(result))
}
pub(crate) async fn ingest_v2(
    State(state): State<AppState>,
    Json(request): Json<IngestRequest>,
) -> Result<Json<IngestResponse>, ApiError> {
    Ok(Json(process(&state, request, true).await?))
}
async fn process(
    state: &AppState,
    request: IngestRequest,
    v2: bool,
) -> Result<IngestResponse, ApiError> {
    if request.device_id.is_empty() || request.frames.is_empty() || request.frames.len() > MAX_BATCH
    {
        return Err(ApiError::BadRequest(
            "device and 1..500 frames required".into(),
        ));
    }
    state
        .store
        .upsert_device(
            &request.device_id,
            &request.model,
            request.firmware.as_deref(),
        )
        .await?;
    let mut response = IngestResponse::default();
    for f in request.frames {
        let id = f.upload_id.as_ref().map(|s| s.to_ascii_lowercase());
        let mut receipt = Receipt {
            client_seq: f.client_seq,
            upload_id: id.clone(),
            status: "rejected",
            reason: None,
        };
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(&f.bytes)
            .ok();
        let reason = if f.client_seq <= 0 {
            Some("invalid_sequence")
        } else if ![3, 4, 5, 7].contains(&f.channel) {
            Some("invalid_channel")
        } else if id.as_ref().is_some_and(|s| !valid_id(s)) || (!v2 && id.is_some()) {
            Some("invalid_upload_id")
        } else if bytes
            .as_ref()
            .is_none_or(|b| zoop_proto::Frame::parse(b).is_err())
        {
            Some("invalid_frame")
        } else {
            None
        };
        if let (None, Some(bytes)) = (reason, bytes.as_ref()) {
            let outcome = state
                .store
                .insert_raw_frame(&NewRawFrame {
                    device_id: &request.device_id,
                    client_seq: f.client_seq,
                    upload_id: id.as_deref(),
                    channel: f.channel,
                    received_at: f.received_at,
                    bytes,
                })
                .await?;
            match outcome {
                IngestOutcome::Stored => {
                    receipt.status = "stored";
                    response.accepted += 1;
                }
                IngestOutcome::Duplicate => {
                    receipt.status = "duplicate";
                    response.duplicates += 1;
                }
                IngestOutcome::Conflict => {
                    receipt.status = "conflict";
                    receipt.reason = Some("identity_content_mismatch");
                    response.rejected += 1;
                }
            }
        } else {
            receipt.reason = reason;
            response.rejected += 1;
        }
        response.results.push(receipt);
    }
    Ok(response)
}
fn valid_id(id: &str) -> bool {
    id.len() == 36
        && id.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}
