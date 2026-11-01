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

#[derive(Debug, Clone, FromRow, serde::Serialize, serde::Deserialize)]
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
        let fail = |e| StorageError::unavailable(StoreOperation::UpsertProfile, e);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let first: bool = sqlx::query_scalar(
            "SELECT NOT EXISTS(SELECT 1 FROM profile_revisions WHERE device_id=$1)",
        )
        .bind(profile.device_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(fail)?;
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
        .execute(&mut *tx)
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertProfile, source))?;
        sqlx::query("INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,CASE WHEN EXISTS(SELECT 1 FROM profile_revisions WHERE device_id=$1) THEN now() ELSE '-infinity'::timestamptz END,to_jsonb(p) FROM profiles p WHERE device_id=$1")
            .bind(profile.device_id).execute(&mut *tx).await.map_err(fail)?;
        sqlx::query("UPDATE analysis_jobs SET generation=generation+1,available_at=now(),backfill=true WHERE device_id=$1 AND kind='workout' AND ($3 OR day >= (now() AT TIME ZONE $2)::date)")
            .bind(profile.device_id).bind(profile.tz).bind(first).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(())
    }
    /// Profile effective before a historical day's end; old history uses the bootstrap snapshot.
    /// # Errors
    /// Database failure or an invalid stored profile.
    pub async fn profile_at(
        &self,
        device: &str,
        cutoff: DateTime<Utc>,
    ) -> StorageResult<Option<ProfileRow>> {
        let value:Option<serde_json::Value>=sqlx::query_scalar("SELECT profile FROM profile_revisions WHERE device_id=$1 AND effective_at<$2 ORDER BY effective_at DESC,id DESC LIMIT 1")
            .bind(device).bind(cutoff).fetch_optional(self.pool()).await.map_err(|e|StorageError::unavailable(StoreOperation::GetProfile,e))?;
        value
            .map(serde_json::from_value)
            .transpose()
            .map_err(|e| StorageError::invalid_data(StoreOperation::GetProfile, e.to_string()))
    }
}
