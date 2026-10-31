//! Samples in, nightly sleep results out.

use chrono::{DateTime, NaiveDate, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

/// A full one-second row, as the analytics need it.
#[derive(Debug, Clone, FromRow)]
pub struct SampleFull {
    pub ts: DateTime<Utc>,
    pub hr: Option<i16>,
    pub rr_ms: Option<Vec<i32>>,
    pub accel_dyn_g: Option<f32>,
    pub gravity_x: Option<f32>,
    pub gravity_y: Option<f32>,
    pub gravity_z: Option<f32>,
    pub skin_temp_c: Option<f32>,
    /// The strap's cumulative step counter.
    pub steps: Option<i32>,
    /// The strap's activity label: 0 still, 1 walk, 2 run.
    pub activity: Option<i16>,
    pub band_state: i16,
    pub spo2_pct: Option<i16>,
}

#[derive(Debug, Clone)]
pub struct NewSleep<'a> {
    pub device_id: &'a str,
    pub night_of: NaiveDate,
    pub algo_version: i32,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub stages: serde_json::Value,
    pub metrics: serde_json::Value,
}

#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct SleepRow {
    pub night_of: NaiveDate,
    pub algo_version: i32,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub stages: serde_json::Value,
    pub metrics: serde_json::Value,
}

impl PostgresStore {
    pub async fn list_device_ids(&self) -> StorageResult<Vec<String>> {
        sqlx::query_scalar("SELECT id FROM devices ORDER BY id")
            .fetch_all(self.pool())
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::ListDevices, source))
    }

    /// Samples in `[from, to)`, ordered by time.
    pub async fn fetch_samples(
        &self,
        device_id: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<SampleFull>> {
        sqlx::query_as(
            "SELECT ts, hr, rr_ms, accel_dyn_g, gravity_x, gravity_y, gravity_z, skin_temp_c,
                    steps, activity, band_state, spo2_pct
             FROM samples WHERE device_id = $1 AND ts >= $2 AND ts < $3 ORDER BY ts",
        )
        .bind(device_id)
        .bind(from)
        .bind(to)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::SamplesInRange, source))
    }

    /// Most recent sample time for a device, if any.
    pub async fn latest_sample_ts(&self, device_id: &str) -> StorageResult<Option<DateTime<Utc>>> {
        sqlx::query_scalar("SELECT max(ts) FROM samples WHERE device_id = $1")
            .bind(device_id)
            .fetch_one(self.pool())
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::LatestSample, source))
    }

    /// Highest one-minute mean heart rate over the trailing `days`, any state. A
    /// minute mean is robust to single-sample glitches where a raw maximum is not.
    pub async fn observed_hr_max(&self, device_id: &str, days: i32) -> StorageResult<Option<f64>> {
        sqlx::query_scalar(
            "SELECT max(m)::float8 FROM (
               SELECT avg(hr) AS m FROM samples
               WHERE device_id = $1 AND hr > 0 AND ts > now() - make_interval(days => $2)
               GROUP BY date_trunc('minute', ts)
             ) minutes",
        )
        .bind(device_id)
        .bind(days)
        .fetch_one(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ObservedHrMax, source))
    }

    pub async fn upsert_sleep(&self, sleep: &NewSleep<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO sleeps (device_id, night_of, algo_version, start_ts, end_ts, stages, metrics)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (device_id, night_of, algo_version) DO UPDATE SET
               start_ts = EXCLUDED.start_ts, end_ts = EXCLUDED.end_ts,
               stages = EXCLUDED.stages, metrics = EXCLUDED.metrics",
        )
        .bind(sleep.device_id)
        .bind(sleep.night_of)
        .bind(sleep.algo_version)
        .bind(sleep.start_ts)
        .bind(sleep.end_ts)
        .bind(&sleep.stages)
        .bind(&sleep.metrics)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertSleep, source))?;
        Ok(())
    }

    pub async fn delete_sleep(
        &self,
        device_id: &str,
        night_of: NaiveDate,
        algo_version: i32,
    ) -> StorageResult<()> {
        sqlx::query(
            "DELETE FROM sleeps WHERE device_id = $1 AND night_of = $2 AND algo_version = $3",
        )
        .bind(device_id)
        .bind(night_of)
        .bind(algo_version)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertSleep, source))?;
        Ok(())
    }

    pub async fn get_sleep(
        &self,
        device_id: &str,
        night_of: NaiveDate,
        algo_version: i32,
    ) -> StorageResult<Option<SleepRow>> {
        sqlx::query_as(
            "SELECT night_of, algo_version, start_ts, end_ts, stages, metrics FROM sleeps
             WHERE device_id = $1 AND night_of = $2 AND algo_version = $3",
        )
        .bind(device_id)
        .bind(night_of)
        .bind(algo_version)
        .fetch_optional(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListSleeps, source))
    }

    /// Latest nights first, current algorithm version only.
    pub async fn list_sleeps(
        &self,
        device_id: &str,
        algo_version: i32,
        limit: i64,
    ) -> StorageResult<Vec<SleepRow>> {
        sqlx::query_as(
            "SELECT night_of, algo_version, start_ts, end_ts, stages, metrics FROM sleeps
             WHERE device_id = $1 AND algo_version = $2 ORDER BY night_of DESC LIMIT $3",
        )
        .bind(device_id)
        .bind(algo_version)
        .bind(limit)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListSleeps, source))
    }

    /// Main sleep windows overlapping `[from, to)`, from the newest algorithm version
    /// that analysed each night, so a version bump does not leave the day's workouts
    /// without a night to exclude.
    pub async fn sleep_windows(
        &self,
        device_id: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<(DateTime<Utc>, DateTime<Utc>)>> {
        sqlx::query_as(
            "SELECT DISTINCT ON (night_of) start_ts, end_ts FROM sleeps
             WHERE device_id = $1 AND end_ts > $2 AND start_ts < $3
             ORDER BY night_of, algo_version DESC",
        )
        .bind(device_id)
        .bind(from)
        .bind(to)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::SleepWindows, source))
    }

    /// Resting heart rate from the most recently analysed night, any version.
    pub async fn latest_resting_hr(&self, device_id: &str) -> StorageResult<Option<f64>> {
        let found: Option<Option<f64>> = sqlx::query_scalar(
            "SELECT (metrics -> 'physiology' ->> 'resting_hr')::float8 FROM sleeps
             WHERE device_id = $1 AND metrics -> 'physiology' ->> 'resting_hr' IS NOT NULL
             ORDER BY night_of DESC, algo_version DESC LIMIT 1",
        )
        .bind(device_id)
        .fetch_optional(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::RestingHr, source))?;
        Ok(found.flatten())
    }
}
