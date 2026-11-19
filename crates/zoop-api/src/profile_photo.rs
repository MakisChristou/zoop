//! Private, bounded JPEG uploads. Decode and re-encode to discard source metadata.
use crate::{AppState, error::ApiError};
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use image::{ImageFormat, ImageReader, Limits, codecs::jpeg::JpegEncoder};
use std::io::Cursor;

pub(crate) const MAX_BYTES: usize = 256 * 1024;
const MAX_DIMENSION: u32 = 512;
const MAX_DECODE_BYTES: u64 = 16 * 1024 * 1024;
const JPEG_QUALITY: u8 = 85;

fn response(jpeg: Vec<u8>) -> Response {
    (
        [
            (header::CONTENT_TYPE, "image/jpeg"),
            (header::CACHE_CONTROL, "private, no-store"),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
        ],
        jpeg,
    )
        .into_response()
}
pub(crate) async fn get(
    State(state): State<AppState>,
    Path(device): Path<String>,
) -> Result<Response, ApiError> {
    state
        .store
        .profile_photo(&device)
        .await?
        .map(response)
        .ok_or(ApiError::NotFound)
}
pub(crate) async fn put(
    State(state): State<AppState>,
    Path(device): Path<String>,
    headers: HeaderMap,
    bytes: Bytes,
) -> Result<Response, ApiError> {
    if headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        != Some("image/jpeg")
    {
        return Err(ApiError::BadRequest("Choose a JPEG profile photo.".into()));
    }
    let jpeg = tokio::task::spawn_blocking(move || normalize(&bytes))
        .await
        .map_err(|_| ApiError::PhotoProcessing)??;
    if !state.store.save_profile_photo(&device, &jpeg).await? {
        return Err(ApiError::NotFound);
    }
    Ok(response(jpeg))
}
pub(crate) async fn delete(
    State(state): State<AppState>,
    Path(device): Path<String>,
) -> Result<StatusCode, ApiError> {
    state.store.remove_profile_photo(&device).await?;
    Ok(StatusCode::NO_CONTENT)
}

fn normalize(bytes: &[u8]) -> Result<Vec<u8>, ApiError> {
    let invalid = |_| {
        ApiError::BadRequest(
            "Choose a valid JPEG photo no larger than 512 pixels and 256 KB.".into(),
        )
    };
    if bytes.is_empty() || bytes.len() > MAX_BYTES {
        return Err(invalid(()));
    }
    let mut reader = ImageReader::with_format(Cursor::new(bytes), ImageFormat::Jpeg);
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_DIMENSION);
    limits.max_image_height = Some(MAX_DIMENSION);
    limits.max_alloc = Some(MAX_DECODE_BYTES);
    reader.limits(limits);
    let image = reader.decode().map_err(|_| invalid(()))?.to_rgb8();
    let mut jpeg = Vec::new();
    JpegEncoder::new_with_quality(&mut jpeg, JPEG_QUALITY)
        .encode_image(&image)
        .map_err(|_| invalid(()))?;
    if jpeg.len() > MAX_BYTES {
        return Err(invalid(()));
    }
    Ok(jpeg)
}

#[cfg(test)]
#[path = "profile_photo/tests.rs"]
mod tests;
