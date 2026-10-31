//! Daily load: zones, training impulse and calories per local day and algorithm
//! version. Read through `list_days`.

use chrono::NaiveDate;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewStrain<'a> {
    pub device_id: &'a str,
    pub day: NaiveDate,
    pub algo_version: i32,
    pub load: f32,
    pub trimp: f32,
    pub zones_min: Vec<i32>,
    pub kcal: Option<f32>,
}

impl PostgresStore {
    pub async fn upsert_strain(&self, strain: &NewStrain<'_>) -> StorageResult<()> {
        sqlx::query(
            "INSERT INTO strains (device_id, day, algo_version, load, trimp, zones_min, kcal)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (device_id, day, algo_version) DO UPDATE SET
               load = EXCLUDED.load, trimp = EXCLUDED.trimp,
               zones_min = EXCLUDED.zones_min, kcal = EXCLUDED.kcal",
        )
        .bind(strain.device_id)
        .bind(strain.day)
        .bind(strain.algo_version)
        .bind(strain.load)
        .bind(strain.trimp)
        .bind(&strain.zones_min)
        .bind(strain.kcal)
        .execute(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::UpsertStrain, source))?;
        Ok(())
    }
}
