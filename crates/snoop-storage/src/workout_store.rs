//! Detected sessions. A day's sessions are replaced as a unit per algorithm version,
//! so re-running a day is idempotent. Reads resolve the user's label on top of the
//! detected kind by time overlap (see `label_store`).

use chrono::{DateTime, Utc};
use sqlx::FromRow;

use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};

#[derive(Debug, Clone)]
pub struct NewWorkout<'a> {
    pub device_id: &'a str,
    pub algo_version: i32,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub kind: &'a str,
    pub load: f32,
    pub avg_hr: f32,
    pub max_hr: i16,
    pub trimp: f32,
    pub zones_min: Vec<i32>,
    pub kcal: Option<f32>,
    pub steps: i32,
}

/// A session as served: `kind` is the user's label when one overlaps, else the
/// detector's `detected_kind`.
#[derive(Debug, Clone, FromRow, serde::Serialize)]
pub struct WorkoutRow {
    pub id: i64,
    pub start_ts: DateTime<Utc>,
    pub end_ts: DateTime<Utc>,
    pub duration_s: i64,
    pub kind: String,
    pub detected_kind: String,
    pub edited: bool,
    pub load: Option<f32>,
    pub avg_hr: Option<f32>,
    pub max_hr: Option<i16>,
    pub trimp: Option<f32>,
    pub zones_min: Option<Vec<i32>>,
    pub kcal: Option<f32>,
    pub steps: Option<i32>,
    pub auto_detected: bool,
}

/// Shared projection: the newest label covering at least half the session wins.
const SELECT_WORKOUT: &str = "
    SELECT w.id, w.start_ts, w.end_ts,
           extract(epoch FROM w.end_ts - w.start_ts)::bigint AS duration_s,
           coalesce(l.kind, w.kind, 'activity') AS kind,
           coalesce(w.kind, 'activity') AS detected_kind,
           (l.kind IS NOT NULL) AS edited,
           w.load, w.avg_hr, w.max_hr, w.trimp, w.zones_min, w.kcal, w.steps, w.auto_detected
    FROM workouts w
    LEFT JOIN LATERAL (
      SELECT kind FROM workout_labels l
      WHERE l.device_id = w.device_id
        AND l.end_ts > w.start_ts AND l.start_ts < w.end_ts
        AND extract(epoch FROM least(l.end_ts, w.end_ts) - greatest(l.start_ts, w.start_ts)) * 2
            >= extract(epoch FROM w.end_ts - w.start_ts)
      ORDER BY l.updated_at DESC LIMIT 1
    ) l ON true
    WHERE w.device_id = $1 AND w.algo_version = $2";

impl PostgresStore {
    /// Stores a day's sessions: rows matching an existing session on its natural key
    /// keep their id so a re-run never looks like a new session, stale sessions in
    /// `[from, to)` are removed, all in one transaction.
    pub async fn sync_workouts(
        &self,
        device_id: &str,
        algo_version: i32,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        workouts: &[NewWorkout<'_>],
    ) -> StorageResult<()> {
        let fail = |source| StorageError::unavailable(StoreOperation::ReplaceWorkouts, source);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let keep: Vec<DateTime<Utc>> = workouts.iter().map(|w| w.start_ts).collect();
        sqlx::query(
            "DELETE FROM workouts
             WHERE device_id = $1 AND algo_version = $2 AND start_ts >= $3 AND start_ts < $4
               AND start_ts <> ALL($5)",
        )
        .bind(device_id)
        .bind(algo_version)
        .bind(from)
        .bind(to)
        .bind(&keep)
        .execute(&mut *tx)
        .await
        .map_err(fail)?;
        for w in workouts {
            sqlx::query(
                "INSERT INTO workouts
                   (device_id, algo_version, start_ts, end_ts, kind, load, avg_hr, max_hr,
                    trimp, zones_min, kcal, steps, auto_detected)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, true)
                 ON CONFLICT (device_id, algo_version, start_ts) DO UPDATE SET
                   end_ts = EXCLUDED.end_ts, kind = EXCLUDED.kind, load = EXCLUDED.load,
                   avg_hr = EXCLUDED.avg_hr, max_hr = EXCLUDED.max_hr, trimp = EXCLUDED.trimp,
                   zones_min = EXCLUDED.zones_min, kcal = EXCLUDED.kcal, steps = EXCLUDED.steps",
            )
            .bind(w.device_id)
            .bind(w.algo_version)
            .bind(w.start_ts)
            .bind(w.end_ts)
            .bind(w.kind)
            .bind(w.load)
            .bind(w.avg_hr)
            .bind(w.max_hr)
            .bind(w.trimp)
            .bind(&w.zones_min)
            .bind(w.kcal)
            .bind(w.steps)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        }
        tx.commit().await.map_err(fail)
    }

    /// Newest sessions first for the algorithm version.
    pub async fn list_workouts(
        &self,
        device_id: &str,
        algo_version: i32,
        limit: i64,
    ) -> StorageResult<Vec<WorkoutRow>> {
        sqlx::query_as(&format!(
            "{SELECT_WORKOUT} ORDER BY w.start_ts DESC LIMIT $3"
        ))
        .bind(device_id)
        .bind(algo_version)
        .bind(limit)
        .fetch_all(self.pool())
        .await
        .map_err(|source| StorageError::unavailable(StoreOperation::ListWorkouts, source))
    }

    pub async fn get_workout(
        &self,
        device_id: &str,
        algo_version: i32,
        id: i64,
    ) -> StorageResult<Option<WorkoutRow>> {
        sqlx::query_as(&format!("{SELECT_WORKOUT} AND w.id = $3"))
            .bind(device_id)
            .bind(algo_version)
            .bind(id)
            .fetch_optional(self.pool())
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::ListWorkouts, source))
    }
}
