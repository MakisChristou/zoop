//! Versioned, source-preserving Health exports and real weight measurements.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::FromRow;

// The app uploads batches: judge the newest complete sample window, with a bounded age.
const WAKE_SAMPLE_MAX_AGE_SECONDS: i64 = 15 * 60;
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::HealthSync, e)
}
/// Stable export identity and server progress; no credentials enter Health metadata.
#[derive(Debug, Serialize, FromRow)]
pub struct HealthInfo {
    pub namespace: String,
    pub cursor: i64,
    pub earliest: Option<DateTime<Utc>>,
    pub wake_at: Option<DateTime<Utc>>,
}
/// A complete replacement for one logical record, or an explicit removal.
#[derive(Debug, Serialize, FromRow)]
pub struct HealthExport {
    pub id: String,
    pub domain: String,
    pub version: i64,
    pub sequence: i64,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub payload: Value,
    pub removed: bool,
}
/// Bounded immutable snapshot/change page. Continue through the same watermark.
#[derive(Debug, Serialize)]
pub struct HealthPage {
    pub namespace: String,
    pub watermark: i64,
    pub next_cursor: i64,
    pub done: bool,
    pub records: Vec<HealthExport>,
}
/// One measured weight, preserving external source ownership.
#[derive(Debug, Serialize, FromRow)]
pub struct WeightReading {
    pub id: String,
    pub measured_at: DateTime<Utc>,
    pub kg: f64,
    pub source: String,
    pub source_name: String,
    pub version: i64,
    pub removed: bool,
}
/// Incremental weight page. Apply by identity/version before durably advancing the cursor.
#[derive(Debug, Serialize)]
pub struct WeightChanges {
    pub rows: Vec<WeightReading>,
    pub next_cursor: i64,
    pub watermark: i64,
    pub done: bool,
}
#[derive(Debug, FromRow)]
struct SequencedWeight {
    change_seq: i64,
    #[sqlx(flatten)]
    reading: WeightReading,
}
/// Retriable weight edit; equal payload retries are acknowledged without revision churn.
#[derive(Debug, Deserialize)]
pub struct WeightInput {
    pub id: String,
    pub measured_at: DateTime<Utc>,
    pub kg: f64,
    pub source: String,
    pub source_name: String,
    pub version: i64,
    #[serde(default)]
    pub removed: bool,
}
/// Step bootstrap progress; callers persist this cursor between bounded requests.
#[derive(Debug, Serialize)]
pub struct HealthPreparation {
    pub next_day: Option<NaiveDate>,
    pub done: bool,
}
impl PostgresStore {
    /// Reads the export namespace and a recently confirmed automatic main-sleep wake.
    /// # Errors
    /// Unknown device or storage failure.
    pub async fn health_info(&self, device: &str) -> StorageResult<HealthInfo> {
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)")
            .bind(device)
            .fetch_one(self.pool())
            .await
            .map_err(fail)?;
        if !exists {
            return Err(StorageError::CorrectionNotFound);
        }
        sqlx::query("INSERT INTO health_datasets(device_id) VALUES($1) ON CONFLICT DO NOTHING")
            .bind(device)
            .execute(self.pool())
            .await
            .map_err(fail)?;
        sqlx::query_as(r#"WITH latest AS (SELECT max(ts) ts FROM samples WHERE device_id=$1 AND ts<=now())
   SELECT namespace::text,cursor,
    (SELECT min(t) FROM (SELECT min(ts) t FROM samples WHERE device_id=$1 UNION ALL SELECT min(measured_at) t FROM weight_readings WHERE device_id=$1) dates) earliest,
    (SELECT max(end_ts) FROM sleep_sessions s WHERE s.device_id=$1 AND kind='main' AND status='active' AND NOT metrics_pending AND NOT edited AND auto_detected
     AND end_ts BETWEEN now()-interval '3 hours' AND now()-interval '30 minutes'
     AND NOT EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='sleep' AND j.tz=s.timezone AND j.day=(s.end_ts AT TIME ZONE s.timezone)::date AND generation>completed_generation)
     AND (SELECT count(*) FILTER(WHERE band_state IN(0,3))>=1500 FROM samples WHERE device_id=$1 AND ts>=s.end_ts AND ts<s.end_ts+interval '30 minutes')
     AND (SELECT ts>=now()-$2::bigint*interval '1 second' FROM latest)
     AND (SELECT count(*) FILTER(WHERE band_state=2)=0 AND count(*)>=240 FROM samples,latest WHERE device_id=$1 AND samples.ts>latest.ts-interval '5 minutes' AND samples.ts<=latest.ts)) wake_at
   FROM health_datasets WHERE device_id=$1"#).bind(device).bind(WAKE_SAMPLE_MAX_AGE_SECONDS).fetch_one(self.pool()).await.map_err(fail)
    }
    /// Pages immutable events; snapshot mode selects only the latest event per identity.
    /// # Errors
    /// Invalid cursors, restored server state, unknown dataset, or storage failure.
    pub async fn health_page(
        &self,
        device: &str,
        after: i64,
        through: Option<i64>,
        snapshot: bool,
        limit: i64,
    ) -> StorageResult<HealthPage> {
        let info = self.health_info(device).await?;
        let watermark = through.unwrap_or(info.cursor);
        if after < 0 || watermark < after || watermark > info.cursor || !(1..=500).contains(&limit)
        {
            return Err(StorageError::CorrectionConflict(
                "Health history changed or the cursor is invalid. Reconnect before continuing."
                    .into(),
            ));
        }
        let records:Vec<HealthExport>=sqlx::query_as(r#"WITH records AS (
   SELECT * FROM health_changes WHERE device_id=$1 AND sequence<=$3 AND NOT $4
   UNION ALL SELECT * FROM (SELECT DISTINCT ON(id) * FROM health_changes WHERE device_id=$1 AND sequence<=$3 AND $4 ORDER BY id,sequence DESC) latest
  ) SELECT id,domain,version,sequence,start_ts,end_ts,payload,removed FROM records WHERE sequence>$2 ORDER BY sequence LIMIT $5"#)
   .bind(device).bind(after).bind(watermark).bind(snapshot).bind(limit+1).fetch_all(self.pool()).await.map_err(fail)?;
        let done = records.len() <= limit as usize;
        let records: Vec<_> = records.into_iter().take(limit as usize).collect();
        let next_cursor = if done {
            watermark
        } else {
            records.last().map_or(after, |r| r.sequence)
        };
        Ok(HealthPage {
            namespace: info.namespace,
            watermark,
            next_cursor,
            done,
            records,
        })
    }
    /// Bootstraps up to three UTC days of steps without rerunning any detector.
    /// # Errors
    /// Invalid interval or storage failure.
    pub async fn prepare_health_steps(
        &self,
        device: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> StorageResult<HealthPreparation> {
        if from > to {
            return Err(StorageError::InvalidQuery(
                "Choose an end date after the start date.".into(),
            ));
        }
        self.health_info(device).await?;
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        let days:Vec<NaiveDate>=sqlx::query_scalar("SELECT d::date FROM generate_series(greatest($2::date,(SELECT (min(ts) AT TIME ZONE 'UTC')::date FROM samples WHERE device_id=$1))::timestamp,least($3::date,(SELECT (max(ts) AT TIME ZONE 'UTC')::date FROM samples WHERE device_id=$1))::timestamp,interval '1 day') d WHERE EXISTS(SELECT 1 FROM samples WHERE device_id=$1) AND NOT EXISTS(SELECT 1 FROM health_step_bootstraps b WHERE b.device_id=$1 AND b.day=d::date) ORDER BY d LIMIT 4")
   .bind(device).bind(from).bind(to).fetch_all(&mut *tx).await.map_err(fail)?;
        for day in days.iter().take(3) {
            sqlx::query("SELECT project_health_steps($1,$2::date::timestamp AT TIME ZONE 'UTC',($2::date+1)::timestamp AT TIME ZONE 'UTC')").bind(device).bind(day).execute(&mut *tx).await.map_err(fail)?;
            sqlx::query("INSERT INTO health_step_bootstraps VALUES($1,$2) ON CONFLICT DO NOTHING")
                .bind(device)
                .bind(day)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
        }
        tx.commit().await.map_err(fail)?;
        Ok(HealthPreparation {
            next_day: days.get(3).copied(),
            done: days.len() <= 3,
        })
    }
    /// Pages every weight in a requested period, without silently truncating history.
    /// # Errors
    /// Storage failure.
    pub async fn weights(
        &self,
        device: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        after: &str,
    ) -> StorageResult<Vec<WeightReading>> {
        self.health_info(device).await?;
        sqlx::query_as("SELECT id,measured_at,kg,source,source_name,version,removed FROM weight_readings WHERE device_id=$1 AND measured_at>=$2 AND measured_at<$3 AND id>$4 ORDER BY id LIMIT 250")
   .bind(device).bind(from).bind(to).bind(after).fetch_all(self.pool()).await.map_err(fail)
    }
    /// Returns changed weights without repeatedly downloading the full history.
    /// Concurrent updates beyond the watermark are picked up by the next pass.
    /// # Errors
    /// Invalid cursor, unknown device, or database failure.
    pub async fn weight_changes(
        &self,
        device: &str,
        after: i64,
        through: Option<i64>,
        limit: i64,
    ) -> StorageResult<WeightChanges> {
        let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)")
            .bind(device)
            .fetch_one(self.pool())
            .await
            .map_err(fail)?;
        if !exists {
            return Err(StorageError::CorrectionNotFound);
        }
        let current: i64 = sqlx::query_scalar(
            "SELECT coalesce((SELECT cursor FROM weight_cursors WHERE device_id=$1),0)",
        )
        .bind(device)
        .fetch_one(self.pool())
        .await
        .map_err(fail)?;
        let watermark = through.unwrap_or(current);
        if after < 0 || watermark < after || watermark > current || !(1..=500).contains(&limit) {
            return Err(StorageError::InvalidQuery(
                "Choose a valid weight history cursor.".into(),
            ));
        }
        let mut rows: Vec<SequencedWeight> = sqlx::query_as("SELECT change_seq,id,measured_at,kg,source,source_name,version,removed FROM weight_readings WHERE device_id=$1 AND change_seq>$2 AND change_seq<=$3 ORDER BY change_seq LIMIT $4")
            .bind(device).bind(after).bind(watermark).bind(limit+1).fetch_all(self.pool()).await.map_err(fail)?;
        let done = rows.len() <= usize::try_from(limit).unwrap_or(0);
        rows.truncate(usize::try_from(limit).unwrap_or(0));
        let next_cursor = if done {
            watermark
        } else {
            rows.last().map_or(after, |r| r.change_seq)
        };
        Ok(WeightChanges {
            rows: rows.into_iter().map(|r| r.reading).collect(),
            next_cursor,
            watermark,
            done,
        })
    }

    /// Saves one measured weight with optimistic concurrency and immutable provenance.
    /// # Errors
    /// Invalid value/identity, conflicting edit, or storage failure.
    pub async fn save_weight(&self, device: &str, w: &WeightInput) -> StorageResult<WeightReading> {
        if !w.kg.is_finite()
            || !(20.0..=400.0).contains(&w.kg)
            || w.id.len() > 100
            || w.id.len() < 8
            || !w
                .id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b":-_".contains(&c))
            || !["snoop", "health"].contains(&w.source.as_str())
            || !w.id.starts_with(&format!("{}:", w.source))
            || w.source_name.len() > 120
            || w.source_name.is_empty()
            || w.measured_at > Utc::now() + chrono::Duration::minutes(5)
            || w.measured_at.timestamp() < 0
            || w.version < 0
        {
            return Err(StorageError::InvalidQuery(
                "Enter a measured weight between 20 and 400 kg, with a valid date and source."
                    .into(),
            ));
        }
        self.health_info(device).await?;
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, device).await?;
        let old:Option<WeightReading>=sqlx::query_as("SELECT id,measured_at,kg,source,source_name,version,removed FROM weight_readings WHERE device_id=$1 AND id=$2 FOR UPDATE")
   .bind(device).bind(&w.id).fetch_optional(&mut *tx).await.map_err(fail)?;
        if let Some(old) = old {
            if old.source != w.source {
                return Err(StorageError::CorrectionConflict(
                    "The measurement source cannot be changed.".into(),
                ));
            }
            if old.measured_at == w.measured_at
                && old.kg == w.kg
                && old.removed == w.removed
                && old.source_name == w.source_name
            {
                return Ok(old);
            }
            if old.version != w.version {
                return Err(StorageError::CorrectionConflict(
                    "This weight changed. Refresh before editing it.".into(),
                ));
            }
        } else if w.version != 0 {
            return Err(StorageError::CorrectionConflict(
                "This weight no longer matches the saved history.".into(),
            ));
        }
        let row=sqlx::query_as("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(device_id,id) DO UPDATE SET measured_at=EXCLUDED.measured_at,kg=EXCLUDED.kg,source_name=EXCLUDED.source_name,removed=EXCLUDED.removed,version=weight_readings.version+1 RETURNING id,measured_at,kg,source,source_name,version,removed")
   .bind(device).bind(&w.id).bind(w.measured_at).bind(w.kg).bind(&w.source).bind(&w.source_name).bind(w.removed).fetch_one(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(row)
    }
    /// Applies explicit Health deletion UUIDs to imported mirrors only. No absence inference.
    /// # Errors
    /// Too many IDs or storage failure.
    pub async fn remove_imported_weights(&self, device: &str, ids: &[String]) -> StorageResult<()> {
        if ids.len() > 250 {
            return Err(StorageError::InvalidQuery(
                "Import at most 250 changes at a time.".into(),
            ));
        }
        sqlx::query("UPDATE weight_readings SET removed=true,version=version+1 WHERE device_id=$1 AND source='health' AND id=ANY($2) AND NOT removed")
   .bind(device).bind(ids).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
}
