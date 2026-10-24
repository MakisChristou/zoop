//! Daily summaries for dashboards: one row per local calendar day.

use chrono::NaiveDate;
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
}

/// Step increments larger than this per second are counter resets or glitches.
const MAX_STEP_INCREMENT_PER_S: i32 = 10;

impl PostgresStore {
    /// Last `limit` days with any samples, oldest first. `tz` is an IANA zone name used
    /// to cut days at local midnight, matching the strap's step counter reset.
    pub async fn list_days(
        &self,
        device_id: &str,
        tz: &str,
        limit: i64,
    ) -> StorageResult<Vec<DayRow>> {
        sqlx::query_as(
            "WITH s AS (
               SELECT (ts AT TIME ZONE $2)::date AS day, ts, hr, steps, activity, skin_temp_c, band_state,
                      steps - lag(steps) OVER (ORDER BY ts) AS inc
               FROM samples WHERE device_id = $1
             )
             SELECT day, steps, steps_walking, walking_s, hr_min, hr_avg, hr_max, skin_temp_avg, asleep_s, samples FROM (
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
             ) d ORDER BY day",
        )
        .bind(device_id)
        .bind(tz)
        .bind(limit)
        .bind(MAX_STEP_INCREMENT_PER_S)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListDays, source))
    }
}
