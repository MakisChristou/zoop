//! Raw frame intake and decode queue. UUID identities survive reinstall counter
//! resets; legacy sequences remain isolated and duplicates require equal content.

use chrono::{DateTime, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewRawFrame<'a> {
    pub device_id: &'a str,
    pub client_seq: i64,
    /// Persisted UUID, or None for an unchanged legacy queue row.
    pub upload_id: Option<&'a str>,
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

/// A duplicate is acknowledged only after comparing the stored content.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum IngestOutcome {
    Stored,
    Duplicate,
    Conflict,
}

impl PostgresStore {
    /// Create/update a reserved device without racing account deletion.
    /// # Errors
    /// Missing ownership or database failure.
    pub async fn upsert_owned_device(
        &self,
        account: i64,
        id: &str,
        model: &str,
        firmware: Option<&str>,
    ) -> StorageResult<()> {
        let mut tx = self
            .pool()
            .begin()
            .await
            .map_err(|e| StorageError::unavailable(StoreOperation::Accounts, e))?;
        require_owner(&mut tx, account, id).await?;
        sqlx::query("INSERT INTO devices(id,model,firmware) VALUES($1,$2,$3) ON CONFLICT(id) DO UPDATE SET model=EXCLUDED.model,firmware=coalesce(EXCLUDED.firmware,devices.firmware)")
            .bind(id).bind(model).bind(firmware).execute(&mut *tx).await.map_err(|e| StorageError::unavailable(StoreOperation::UpsertDevice,e))?;
        tx.commit()
            .await
            .map_err(|e| StorageError::unavailable(StoreOperation::UpsertDevice, e))
    }
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

    /// Stores a frame, or verifies that its immutable identity already has the same bytes.
    /// # Errors
    /// The database is unavailable.
    pub async fn insert_raw_frame(&self, frame: &NewRawFrame<'_>) -> StorageResult<IngestOutcome> {
        self.insert_frame(frame, None).await
    }

    /// Store a frame only while its authenticated account still owns this serial.
    /// # Errors
    /// Revoked ownership or database failure.
    pub async fn insert_owned_raw_frame(
        &self,
        frame: &NewRawFrame<'_>,
        account: i64,
    ) -> StorageResult<IngestOutcome> {
        self.insert_frame(frame, Some(account)).await
    }

    async fn insert_frame(
        &self,
        frame: &NewRawFrame<'_>,
        account: Option<i64>,
    ) -> StorageResult<IngestOutcome> {
        let fail = |e| StorageError::unavailable(StoreOperation::InsertRawFrame, e);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        if let Some(account) = account {
            require_owner(&mut tx, account, frame.device_id).await?;
        }
        let inserted: Option<i64> = sqlx::query_scalar(
            "INSERT INTO raw_frames(device_id,client_seq,upload_id,channel,received_at,bytes)
             VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING RETURNING id",
        )
        .bind(frame.device_id)
        .bind(frame.client_seq)
        .bind(frame.upload_id)
        .bind(frame.channel)
        .bind(frame.received_at)
        .bind(frame.bytes)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        let outcome = if inserted.is_some() {
            IngestOutcome::Stored
        } else {
            let same: bool = sqlx::query_scalar(
                "SELECT bytes=$4 AND channel=$5 FROM raw_frames WHERE device_id=$1 AND
                 (($3::text IS NOT NULL AND upload_id=$3) OR ($3 IS NULL AND upload_id IS NULL AND client_seq=$2))")
                .bind(frame.device_id).bind(frame.client_seq).bind(frame.upload_id)
                .bind(frame.bytes).bind(frame.channel).fetch_one(&mut *tx).await.map_err(fail)?;
            if same {
                IngestOutcome::Duplicate
            } else {
                IngestOutcome::Conflict
            }
        };
        tx.commit().await.map_err(fail)?;
        Ok(outcome)
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

async fn require_owner(
    tx: &mut sqlx::PgConnection,
    account: i64,
    device: &str,
) -> StorageResult<()> {
    let found: Option<i64> = sqlx::query_scalar("SELECT a.id FROM accounts a JOIN device_owners o ON o.account_id=a.id WHERE a.id=$1 AND a.enabled AND o.device_id=$2 FOR SHARE OF a,o")
        .bind(account).bind(device).fetch_optional(tx).await.map_err(|e| StorageError::unavailable(StoreOperation::Accounts,e))?;
    if found.is_none() {
        return Err(StorageError::InvalidQuery(
            "account no longer owns this device".into(),
        ));
    }
    Ok(())
}
