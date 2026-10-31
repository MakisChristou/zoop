//! Body profile and home time zone per device: user input the analytics read.

use chrono::{DateTime, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewProfile<'a> {
    pub device_id: &'a str,
    /// `male` or `female`, as the calorie equations are published.
    pub sex: Option<&'a str>,
    pub birth_year: Option<i16>,
    pub weight_kg: Option<f32>,
    pub height_cm: Option<f32>,
    /// IANA zone the day is cut in.
    pub tz: &'a str,
}

#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct ProfileRow {
    pub sex: Option<String>,
    pub birth_year: Option<i16>,
    pub weight_kg: Option<f32>,
    pub height_cm: Option<f32>,
    pub tz: String,
    pub updated_at: DateTime<Utc>,
}

impl PostgresStore {
    pub async fn get_profile(&self, device_id: &str) -> StorageResult<Option<ProfileRow>> {
        sqlx::query_as(
            "SELECT sex, birth_year, weight_kg, height_cm, tz, updated_at FROM profiles
             WHERE device_id = $1",
        )
        .bind(device_id)
        .fetch_optional(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::GetProfile, source))
    }

    pub async fn upsert_profile(&self, profile: &NewProfile<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO profiles (device_id, sex, birth_year, weight_kg, height_cm, tz, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, now())
             ON CONFLICT (device_id) DO UPDATE SET
               sex = EXCLUDED.sex, birth_year = EXCLUDED.birth_year,
               weight_kg = EXCLUDED.weight_kg, height_cm = EXCLUDED.height_cm,
               tz = EXCLUDED.tz, updated_at = now()",
        )
        .bind(profile.device_id)
        .bind(profile.sex)
        .bind(profile.birth_year)
        .bind(profile.weight_kg)
        .bind(profile.height_cm)
        .bind(profile.tz)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertProfile, source))?;
        Ok(())
    }
}
