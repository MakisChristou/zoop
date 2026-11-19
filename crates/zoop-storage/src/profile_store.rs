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
    /// Provenance of the measured weight, absent for a manual fallback.
    #[serde(default)]
    #[sqlx(default)]
    pub weight_measured_at: Option<DateTime<Utc>>,
    #[serde(default)]
    #[sqlx(default)]
    pub weight_source: Option<String>,
    #[serde(default)]
    #[sqlx(default)]
    pub weight_source_name: Option<String>,
}

impl PostgresStore {
    pub async fn get_profile(&self, device_id: &str) -> StorageResult<Option<ProfileRow>> {
        let profile = sqlx::query_as(
            "SELECT sex, birth_year, weight_kg, height_cm, tz, updated_at FROM profiles
             WHERE device_id = $1",
        )
        .bind(device_id)
        .fetch_optional(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::GetProfile, source))?;
        self.with_measured_weight(profile, device_id, Utc::now())
            .await
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
               weight_kg = CASE WHEN EXISTS(SELECT 1 FROM weight_readings WHERE device_id=$1 AND NOT removed AND measured_at<=now())
                 THEN profiles.weight_kg ELSE EXCLUDED.weight_kg END,
               height_cm = EXCLUDED.height_cm,
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
        let profile = value
            .map(serde_json::from_value)
            .transpose()
            .map_err(|e| StorageError::invalid_data(StoreOperation::GetProfile, e.to_string()))?;
        self.with_measured_weight(profile, device, cutoff).await
    }

    /// Resolve weight by measurement time, not import time. Health wins within the
    /// latest local date; old backfills and future readings cannot replace today.
    async fn with_measured_weight(
        &self,
        profile: Option<ProfileRow>,
        device: &str,
        cutoff: DateTime<Utc>,
    ) -> StorageResult<Option<ProfileRow>> {
        let Some(mut profile) = profile else {
            return Ok(None);
        };
        let reading: Option<(f64, DateTime<Utc>, String, String)> = sqlx::query_as(
            "SELECT kg,measured_at,source,source_name FROM weight_readings
             WHERE device_id=$1 AND NOT removed AND measured_at<$2 AND measured_at<=now()
             ORDER BY (measured_at AT TIME ZONE $3)::date DESC,(source='health') DESC,measured_at DESC,id DESC LIMIT 1"
        ).bind(device).bind(cutoff).bind(&profile.tz).fetch_optional(self.pool()).await
          .map_err(|e| StorageError::unavailable(StoreOperation::GetProfile,e))?;
        if let Some((kg, at, source, name)) = reading {
            #[allow(clippy::cast_possible_truncation)]
            {
                profile.weight_kg = Some(kg as f32);
            }
            profile.weight_measured_at = Some(at);
            profile.weight_source = Some(source);
            profile.weight_source_name = Some(name);
        }
        Ok(Some(profile))
    }
}
