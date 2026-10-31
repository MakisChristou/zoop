//! Daily summaries for dashboards: one row per local calendar day, plus the local
//! calendar helpers the workers use so Postgres stays the one authority on zones.

use chrono::{DateTime, NaiveDate, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct DayRow {
    pub day: NaiveDate,
    /// Sum of the strap counter's positive increments over the day. The counter resets
    /// whenever the strap is taken off or charged, so a sum is the only robust total.
    /// Inflated by arm movement while not walking; see `steps_walking`.
    pub steps: Option<i32>,
    /// Counter increments that happened in seconds the strap labelled walking or
    /// running: its own activity classifier used as a false-step filter.
    pub steps_walking: Option<i64>,
    /// Seconds the strap labelled walking or running.
    pub walking_s: Option<i64>,
    pub hr_min: Option<i16>,
    pub hr_avg: Option<f32>,
    pub hr_max: Option<i16>,
    pub skin_temp_avg: Option<f32>,
    /// Seconds the strap flagged as asleep.
    pub asleep_s: Option<i64>,
    pub samples: i64,
    /// Day load on the 0–21 display scale, from `strains` when the day was analysed.
    pub load: Option<f32>,
    /// Edwards training impulse over the awake day.
    pub trimp: Option<f32>,
    /// Calories over the day's detected sessions.
    pub kcal: Option<f32>,
    /// Minutes in each of the five heart-rate zones.
    pub zones_min: Option<Vec<i32>>,
}

/// Steps in one local hour of a day.
#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct HourSteps {
    pub hour: i32,
    pub steps: i64,
    pub walking: i64,
}

/// Step increments larger than this per second are counter resets or glitches.
const MAX_STEP_INCREMENT_PER_S: i32 = 10;

impl PostgresStore {
    /// Last `limit` days with any samples, oldest first. `tz` is an IANA zone name used
    /// to cut days at local midnight, matching the strap's step counter reset. Load
    /// columns join `strains` at `algo_version`, whose days are cut in the profile's
    /// zone; pass the same zone for them to line up.
    pub async fn list_days(
        &self,
        device_id: &str,
        tz: &str,
        limit: i64,
        algo_version: i32,
    ) -> StorageResult<Vec<DayRow>> {
        sqlx::query_as(
            "WITH s AS (
               SELECT (ts AT TIME ZONE $2)::date AS day, ts, hr, steps, activity, skin_temp_c, band_state,
                      steps - lag(steps) OVER (ORDER BY ts) AS inc
               FROM samples WHERE device_id = $1
             ), d AS (
               SELECT day,
                      sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4)::int AS steps,
                      sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4 AND activity IN (1, 2))::bigint AS steps_walking,
                      count(*) FILTER (WHERE activity IN (1, 2))::bigint AS walking_s,
                      min(hr) FILTER (WHERE hr > 0) AS hr_min,
                      avg(hr) FILTER (WHERE hr > 0)::real AS hr_avg,
                      max(hr) AS hr_max,
                      avg(skin_temp_c)::real AS skin_temp_avg,
                      count(*) FILTER (WHERE band_state = 2)::bigint AS asleep_s,
                      count(*)::bigint AS samples
               FROM s GROUP BY day ORDER BY day DESC LIMIT $3
             )
             SELECT d.day, d.steps, d.steps_walking, d.walking_s, d.hr_min, d.hr_avg, d.hr_max,
                    d.skin_temp_avg, d.asleep_s, d.samples,
                    st.load, st.trimp, st.kcal, st.zones_min
             FROM d LEFT JOIN strains st
               ON st.device_id = $1 AND st.day = d.day AND st.algo_version = $5
             ORDER BY d.day",
        )
        .bind(device_id)
        .bind(tz)
        .bind(limit)
        .bind(MAX_STEP_INCREMENT_PER_S)
        .bind(algo_version)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListDays, source))
    }

    /// Steps per local hour of one day, hours with no steps omitted. The increment of
    /// the day's first sample is taken against the last sample before midnight.
    pub async fn hourly_steps(
        &self,
        device_id: &str,
        day: NaiveDate,
        tz: &str,
    ) -> StorageResult<Vec<HourSteps>> {
        sqlx::query_as(
            "WITH s AS (
               SELECT ts, activity, steps - lag(steps) OVER (ORDER BY ts) AS inc
               FROM samples
               WHERE device_id = $1
                 AND ts >= ($2::date::timestamp AT TIME ZONE $3) - interval '1 second'
                 AND ts < (($2::date + 1)::timestamp AT TIME ZONE $3)
             )
             SELECT extract(hour FROM ts AT TIME ZONE $3)::int AS hour,
                    coalesce(sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4), 0)::bigint AS steps,
                    coalesce(sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4 AND activity IN (1, 2)), 0)::bigint AS walking
             FROM s WHERE ts >= ($2::date::timestamp AT TIME ZONE $3)
             GROUP BY 1 ORDER BY 1",
        )
        .bind(device_id)
        .bind(day)
        .bind(tz)
        .bind(MAX_STEP_INCREMENT_PER_S)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::HourlySteps, source))
    }

    /// UTC instants of local midnight starting and ending `day` in `tz`.
    pub async fn local_day_bounds(
        &self,
        day: NaiveDate,
        tz: &str,
    ) -> StorageResult<(DateTime<Utc>, DateTime<Utc>)> {
        sqlx::query_as(
            "SELECT ($1::date::timestamp AT TIME ZONE $2), (($1::date + 1)::timestamp AT TIME ZONE $2)",
        )
        .bind(day)
        .bind(tz)
        .fetch_one(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::LocalDay, source))
    }

    /// Today's date in `tz`. Fails when `tz` is not a zone Postgres knows.
    pub async fn local_today(&self, tz: &str) -> StorageResult<NaiveDate> {
        sqlx::query_scalar("SELECT (now() AT TIME ZONE $1)::date")
            .bind(tz)
            .fetch_one(self.pool())
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::LocalDay, source))
    }
}
