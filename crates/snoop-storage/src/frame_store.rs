//! Raw frame intake and the decode work queue. The `(device_id, client_seq)` unique
//! constraint makes ingest idempotent across phone retries.

use chrono::{DateTime, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewRawFrame<'a> {
    pub device_id: &'a str,
    pub client_seq: i64,
    pub channel: i16,
    pub received_at: DateTime<Utc>,
    pub bytes: &'a [u8],
}

#[derive(Debug, Clone, FromRow)]
pub struct PendingFrame {
    pub id: i64,
    pub device_id: String,
    pub received_at: DateTime<Utc>,
    pub bytes: Vec<u8>,
}

impl PostgresStore {
    pub async fn upsert_device(
        &self,
        id: &str,
        model: &str,
        firmware: Option<&str>,
    ) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO devices (id, model, firmware) VALUES ($1, $2, $3)
             ON CONFLICT (id) DO UPDATE
             SET model = EXCLUDED.model,
                 firmware = COALESCE(EXCLUDED.firmware, devices.firmware)",
        )
        .bind(id)
        .bind(model)
        .bind(firmware)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertDevice, source))?;
        Ok(())
    }

    /// Returns `true` when the frame was new, `false` when it was a duplicate.
    pub async fn insert_raw_frame(&self, frame: &NewRawFrame<'_>) -> StorageResult<bool> {
        let result = sqlx::query(
            "INSERT INTO raw_frames (device_id, client_seq, channel, received_at, bytes)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (device_id, client_seq) DO NOTHING",
        )
        .bind(frame.device_id)
        .bind(frame.client_seq)
        .bind(frame.channel)
        .bind(frame.received_at)
        .bind(frame.bytes)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::InsertRawFrame, source))?;
        Ok(result.rows_affected() == 1)
    }

    /// Frames never decoded, or decoded by an older protocol version than `proto_version`.
    pub async fn fetch_pending_frames(
        &self,
        proto_version: i32,
        limit: i64,
    ) -> StorageResult<Vec<PendingFrame>> {
        if limit <= 0 {
            return Err(StorageError::invalid_data(
                StoreOperation::FetchPendingFrames,
                "limit must be positive",
            ));
        }
        sqlx::query_as(
            "SELECT id, device_id, received_at, bytes FROM raw_frames
             WHERE decoded_proto IS NULL OR decoded_proto < $1
             ORDER BY id
             LIMIT $2",
        )
        .bind(proto_version)
        .bind(limit)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::FetchPendingFrames, source))
    }

    pub async fn mark_frame_decoded(&self, frame_id: i64, proto_version: i32) -> StorageResult<()> {
        sqlx::query("UPDATE raw_frames SET decoded_proto = $1 WHERE id = $2")
            .bind(proto_version)
            .bind(frame_id)
            .execute(self.pool())
            .await
            .map_err(|source| {
                StorageError::unavailable(StoreOperation::MarkFrameDecoded, source)
            })?;
        Ok(())
    }
}
