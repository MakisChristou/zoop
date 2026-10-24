//! Daily summaries for dashboards: one row per local calendar day.

use chrono::NaiveDate;
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct DayRow {
    pub day: NaiveDate,
    /// The strap's step counter resets at local midnight; the day's maximum is the total.
    pub steps: Option<i32>,
    pub hr_min: Option<i16>,
    pub hr_avg: Option<f32>,
    pub hr_max: Option<i16>,
    pub skin_temp_avg: Option<f32>,
    /// Seconds the strap flagged as asleep.
    pub asleep_s: Option<i64>,
    pub samples: i64,
}

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
            "SELECT day, steps, hr_min, hr_avg, hr_max, skin_temp_avg, asleep_s, samples FROM (
               SELECT (ts AT TIME ZONE $2)::date AS day,
                      max(steps) AS steps,
                      min(hr) FILTER (WHERE hr > 0) AS hr_min,
                      avg(hr) FILTER (WHERE hr > 0)::real AS hr_avg,
                      max(hr) AS hr_max,
                      avg(skin_temp_c)::real AS skin_temp_avg,
                      count(*) FILTER (WHERE band_state = 2)::bigint AS asleep_s,
                      count(*)::bigint AS samples
               FROM samples WHERE device_id = $1
               GROUP BY 1 ORDER BY 1 DESC LIMIT $3
             ) d ORDER BY day",
        )
        .bind(device_id)
        .bind(tz)
        .bind(limit)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListDays, source))
    }
}
