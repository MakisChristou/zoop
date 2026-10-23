//! Decoded sensor rows. Re-decoding the same raw frame upserts, so backfills are
//! idempotent.

use chrono::{DateTime, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewSample<'a> {
    pub device_id: &'a str,
    pub ts: DateTime<Utc>,
    pub hr: Option<i16>,
    pub rr_ms: Vec<i32>,
    pub skin_temp_c: Option<f32>,
    pub steps: Option<i32>,
    pub accel_dyn_g: Option<f32>,
    pub activity: Option<i16>,
    pub band_state: i16,
    pub spo2_pct: Option<i16>,
    pub raw_frame_id: i64,
}

#[derive(Debug, Clone)]
pub struct NewEvent<'a> {
    pub device_id: &'a str,
    pub ts: DateTime<Utc>,
    pub event_code: i16,
    pub payload: Vec<u8>,
    pub raw_frame_id: i64,
}

#[derive(Debug, Clone)]
pub struct NewEcgStrip<'a> {
    pub device_id: &'a str,
    pub ts: DateTime<Utc>,
    pub layout: i16,
    pub quality: Option<i16>,
    pub samples: Vec<i32>,
    pub raw_frame_id: i64,
}

#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct SampleRow {
    pub ts: DateTime<Utc>,
    pub hr: Option<i16>,
    pub skin_temp_c: Option<f32>,
    pub steps: Option<i32>,
    pub band_state: Option<i16>,
}

impl PostgresStore {
    pub async fn upsert_sample(&self, sample: &NewSample<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO samples
               (device_id, ts, hr, rr_ms, skin_temp_c, steps, accel_dyn_g, activity, band_state, spo2_pct, raw_frame_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
             ON CONFLICT (device_id, ts) DO UPDATE SET
               hr = EXCLUDED.hr,
               rr_ms = EXCLUDED.rr_ms,
               skin_temp_c = EXCLUDED.skin_temp_c,
               steps = EXCLUDED.steps,
               accel_dyn_g = EXCLUDED.accel_dyn_g,
               activity = EXCLUDED.activity,
               band_state = EXCLUDED.band_state,
               spo2_pct = EXCLUDED.spo2_pct,
               raw_frame_id = EXCLUDED.raw_frame_id",
        )
        .bind(sample.device_id)
        .bind(sample.ts)
        .bind(sample.hr)
        .bind(&sample.rr_ms)
        .bind(sample.skin_temp_c)
        .bind(sample.steps)
        .bind(sample.accel_dyn_g)
        .bind(sample.activity)
        .bind(sample.band_state)
        .bind(sample.spo2_pct)
        .bind(sample.raw_frame_id)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertSample, source))?;
        Ok(())
    }

    pub async fn insert_event(&self, event: &NewEvent<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO events (device_id, ts, event_code, payload, raw_frame_id)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(event.device_id)
        .bind(event.ts)
        .bind(event.event_code)
        .bind(&event.payload)
        .bind(event.raw_frame_id)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::InsertEvent, source))?;
        Ok(())
    }

    pub async fn insert_ecg_strip(&self, strip: &NewEcgStrip<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO ecg_strips (device_id, ts, layout, quality, samples, raw_frame_id)
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(strip.device_id)
        .bind(strip.ts)
        .bind(strip.layout)
        .bind(strip.quality)
        .bind(&strip.samples)
        .bind(strip.raw_frame_id)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::InsertEcgStrip, source))?;
        Ok(())
    }

    pub async fn latest_sample(&self, device_id: &str) -> StorageResult<Option<SampleRow>> {
        sqlx::query_as(
            "SELECT ts, hr, skin_temp_c, steps, band_state FROM samples
             WHERE device_id = $1 ORDER BY ts DESC LIMIT 1",
        )
        .bind(device_id)
        .fetch_optional(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::LatestSample, source))
    }

    /// Minute-averaged samples in `[start, end)`.
    pub async fn samples_in_range(
        &self,
        device_id: &str,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> StorageResult<Vec<SampleRow>> {
        sqlx::query_as(
            "SELECT date_trunc('minute', ts) AS ts,
                    avg(hr)::smallint AS hr,
                    avg(skin_temp_c)::real AS skin_temp_c,
                    max(steps) AS steps,
                    mode() WITHIN GROUP (ORDER BY band_state)::smallint AS band_state
             FROM samples
             WHERE device_id = $1 AND ts >= $2 AND ts < $3
             GROUP BY 1 ORDER BY 1",
        )
        .bind(device_id)
        .bind(start)
        .bind(end)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::SamplesInRange, source))
    }
}
