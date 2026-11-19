//! Transactional corrections and the effective workout projection. Both mutation
//! and worker publication lock the device before jobs, so generation fencing also
//! covers edits arriving during a calculation. Detector candidates remain intact.

use crate::{
    PostgresStore, SessionDomain, StorageError, StorageResult, StoreOperation,
    session::{
        CorrectionReceipt, CorrectionScope, SessionCalculation, SessionMetrics, WorkoutCorrection,
        WorkoutSession,
    },
};
use chrono::{DateTime, Duration, Utc};
use serde_json::{Value, json};
use sqlx::{PgConnection, types::Json};

const MAX_WORKOUT_HOURS: i64 = 24;
const MAX_COMMAND_TARGETS: usize = 20;
pub(crate) const SELECT: &str = "SELECT id,start_ts,end_ts,duration_s,kind,detected_kind,edited,fixed,auto_detected,notification_eligible,revision,status,last_edit,replacements,metrics,metrics_pending,timezone FROM workout_sessions";
pub(crate) fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::CorrectWorkout, e)
}
pub(crate) fn invalid(message: &str) -> StorageError {
    StorageError::InvalidCorrection(message.to_owned())
}
pub(crate) fn conflict(message: &str) -> StorageError {
    StorageError::CorrectionConflict(message.to_owned())
}

/// Serialises writers for a strap without locking raw ingestion or sensor samples.
pub(crate) async fn lock_device(tx: &mut PgConnection, device: &str) -> StorageResult<()> {
    let found: Option<String> = sqlx::query_scalar("SELECT id FROM devices WHERE id=$1 FOR UPDATE")
        .bind(device)
        .fetch_optional(tx)
        .await
        .map_err(fail)?;
    if found.is_none() {
        return Err(StorageError::CorrectionNotFound);
    }
    Ok(())
}

/// A single correction engine, with separate data and ownership for each domain.
#[derive(Debug, Clone, Copy)]
pub struct SessionStore<'a> {
    pub(crate) store: &'a PostgresStore,
    pub(crate) domain: SessionDomain,
}
impl SessionStore<'_> {
    /// Lists effective sessions by overlap, including cross-midnight workouts.
    /// # Errors
    /// Database failure.
    pub async fn list_sessions(
        &self,
        device: &str,
        status: &str,
        from: Option<DateTime<Utc>>,
        to: Option<DateTime<Utc>>,
        limit: i64,
    ) -> StorageResult<Vec<WorkoutSession>> {
        sqlx::query_as(&sql(self.domain, &format!("{SELECT} WHERE device_id=$1 AND status=$2 AND ($3::timestamptz IS NULL OR end_ts>$3) AND ($4::timestamptz IS NULL OR start_ts<$4) ORDER BY start_ts DESC,id DESC LIMIT $5")))
            .bind(device).bind(status).bind(from).bind(to).bind(limit).fetch_all(self.store.pool()).await.map_err(fail)
    }
    /// Resolves stable ids and pre-migration notification ids, including tombstones.
    /// # Errors
    /// Database failure.
    pub async fn get_session(
        &self,
        device: &str,
        id: i64,
    ) -> StorageResult<Option<WorkoutSession>> {
        sqlx::query_as(&sql(self.domain, &format!("{SELECT} WHERE device_id=$1 AND id=coalesce((SELECT id FROM workout_sessions WHERE device_id=$1 AND id=$2),(SELECT session_id FROM workout_aliases WHERE legacy_id=$2))")))
            .bind(device).bind(id).fetch_optional(self.store.pool()).await.map_err(fail)
    }
    /// All user-owned intervals intersecting a calculation window.
    /// # Errors
    /// Database failure.
    pub async fn correction_scopes(
        &self,
        device: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<CorrectionScope>> {
        sqlx::query_as(&sql(self.domain, "SELECT scope_start AS start_ts,scope_end AS end_ts FROM workout_corrections WHERE device_id=$1 AND active AND scope_start<$3 AND scope_end>$2 ORDER BY scope_start"))
            .bind(device).bind(from).bind(to).fetch_all(self.store.pool()).await.map_err(fail)
    }
    /// Fixed windows needed for interval metrics and calendar-day calorie allocation.
    /// # Errors
    /// Database failure.
    pub async fn fixed_sessions(
        &self,
        device: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<WorkoutSession>> {
        sqlx::query_as(&sql(self.domain, &format!("{SELECT} WHERE device_id=$1 AND status='active' AND fixed AND end_ts>$2 AND start_ts<$3 ORDER BY start_ts")))
            .bind(device).bind(from).bind(to).fetch_all(self.store.pool()).await.map_err(fail)
    }
    /// Atomically saves a correction, its undo snapshot, and all affected analysis jobs.
    /// # Errors
    /// Invalid intervals, missing data, overlapping workouts, stale revisions,
    /// mismatched idempotency keys, or database failure. No partial mutation is saved.
    pub async fn correct_workout(
        &self,
        device: &str,
        command: &WorkoutCorrection,
        version: i32,
    ) -> StorageResult<CorrectionReceipt> {
        validate_command(command, self.domain)?;
        let payload = serde_json::to_value(command)
            .map_err(|e| StorageError::unavailable(StoreOperation::CorrectWorkout, e))?;
        let mut tx = self.store.pool().begin().await.map_err(fail)?;
        lock_device(&mut tx, device).await?;
        let previous: Option<(String, Value, Vec<i64>)> = sqlx::query_as(&sql(
            self.domain,
            "SELECT device_id,request,affected_ids FROM workout_corrections WHERE operation_id=$1",
        ))
        .bind(&command.operation_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        if let Some((owner, request, ids)) = previous {
            if owner != device || request != payload {
                return Err(conflict(
                    "This save request has already been used. Reopen the editor and try again.",
                ));
            }
            return Ok(CorrectionReceipt {
                operation_id: command.operation_id.clone(),
                workout_ids: ids,
            });
        }
        if command.action == "undo" {
            let receipt = undo(&mut tx, self.domain, device, command, payload, version).await?;
            tx.commit().await.map_err(fail)?;
            return Ok(receipt);
        }
        let mut before = Vec::new();
        for target in &command.targets {
            let row: WorkoutSession = sqlx::query_as(&sql(
                self.domain,
                &format!("{SELECT} WHERE device_id=$1 AND id=$2"),
            ))
            .bind(device)
            .bind(target.id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(fail)?
            .ok_or(StorageError::CorrectionNotFound)?;
            if row.status != "active" || row.revision != target.revision {
                return Err(conflict(
                    "This recording has changed. Close the editor, refresh, and try again.",
                ));
            }
            before.push(row);
        }
        before.sort_by_key(|w| (w.start_ts, w.id));
        validate_shape(command, &before)?;
        let ids: Vec<_> = before.iter().map(|w| w.id).collect();
        for interval in &command.intervals {
            let exists: bool=sqlx::query_scalar(&sql(self.domain, "SELECT EXISTS(SELECT 1 FROM samples WHERE device_id=$1 AND ts >= $2 AND ts < $3 AND (hr>0 OR steps IS NOT NULL OR activity IS NOT NULL OR accel_dyn_g IS NOT NULL))"))
                .bind(device).bind(interval.start_ts).bind(interval.end_ts).fetch_one(&mut *tx).await.map_err(fail)?;
            if !exists {
                return Err(invalid(
                    "No strap data in this time range. Sync your WHOOP or choose another time.",
                ));
            }
            let overlaps: bool=sqlx::query_scalar(&sql(self.domain, "SELECT EXISTS(SELECT 1 FROM workout_sessions WHERE device_id=$1 AND status='active' AND id<>ALL($4) AND start_ts<$3 AND end_ts>$2)"))
                .bind(device).bind(interval.start_ts).bind(interval.end_ts).bind(&ids).fetch_one(&mut *tx).await.map_err(fail)?;
            if overlaps {
                return Err(conflict(
                    "Another recording overlaps this time. Adjust the times or merge the recordings.",
                ));
            }
        }
        let tz: String = sqlx::query_scalar(&sql(
            self.domain,
            "SELECT coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC')",
        ))
        .bind(device)
        .fetch_one(&mut *tx)
        .await
        .map_err(fail)?;
        if self.domain == SessionDomain::Sleep {
            check_main(
                &mut tx,
                device,
                &command.intervals,
                &ids,
                before.first().map_or(tz.as_str(), |r| r.timezone.as_str()),
            )
            .await?;
        }
        let mut after = before.clone();
        let mut output_ids = Vec::new();
        for (i, interval) in command.intervals.iter().enumerate() {
            let mut row = if i == 0 && !before.is_empty() {
                before[0].clone()
            } else {
                let id: i64 =
                    sqlx::query_scalar(&sql(self.domain, "SELECT nextval('workouts_id_seq')"))
                        .fetch_one(&mut *tx)
                        .await
                        .map_err(fail)?;
                WorkoutSession {
                    id,
                    start_ts: interval.start_ts,
                    end_ts: interval.end_ts,
                    duration_s: 0,
                    kind: interval.kind.clone(),
                    detected_kind: before
                        .first()
                        .map_or_else(|| interval.kind.clone(), |w| w.detected_kind.clone()),
                    edited: true,
                    fixed: true,
                    auto_detected: command.action != "add",
                    notification_eligible: false,
                    revision: 0,
                    status: "active".to_owned(),
                    last_edit: None,
                    replacements: vec![],
                    metrics: Json(SessionMetrics::default()),
                    metrics_pending: true,
                    timezone: before
                        .first()
                        .map_or_else(|| tz.clone(), |r| r.timezone.clone()),
                }
            };
            row.start_ts = interval.start_ts;
            row.end_ts = interval.end_ts;
            row.duration_s = (row.end_ts - row.start_ts).num_seconds();
            row.kind = interval.kind.clone();
            row.edited = true;
            row.fixed = true;
            row.revision += 1;
            row.last_edit = Some(command.operation_id.clone());
            row.notification_eligible = false;
            row.metrics = Json(SessionMetrics::default());
            row.metrics_pending = true;
            output_ids.push(row.id);
            if i == 0 && !after.is_empty() {
                after[0] = row;
            } else {
                after.push(row);
            }
        }
        for row in &mut after {
            if !output_ids.contains(&row.id) {
                row.status = if command.action == "remove" {
                    "removed"
                } else {
                    "superseded"
                }
                .to_owned();
                row.replacements = output_ids.clone();
                row.last_edit = Some(command.operation_id.clone());
                row.revision += 1;
                row.notification_eligible = false;
            }
        }
        let scope_start = before
            .iter()
            .map(|w| w.start_ts)
            .chain(command.intervals.iter().map(|w| w.start_ts))
            .min()
            .ok_or_else(|| invalid("Choose a workout to change."))?;
        let scope_end = before
            .iter()
            .map(|w| w.end_ts)
            .chain(command.intervals.iter().map(|w| w.end_ts))
            .max()
            .ok_or_else(|| invalid("Choose a workout to change."))?;
        let affected: Vec<_> = after.iter().map(|w| w.id).collect();
        for row in &after {
            persist(&mut tx, self.domain, device, row).await?;
        }
        let owns = true;
        sqlx::query(&sql(self.domain, "INSERT INTO workout_corrections(operation_id,device_id,request,before_state,affected_ids,scope_start,scope_end) VALUES($1,$2,$3,$4,$5,$6,$7)"))
            .bind(&command.operation_id).bind(device).bind(payload).bind(json!(before)).bind(&affected)
            .bind(owns.then_some(scope_start)).bind(owns.then_some(scope_end)).execute(&mut *tx).await.map_err(fail)?;
        invalidate(
            &mut tx,
            self.domain,
            device,
            scope_start,
            scope_end,
            &tz,
            version,
        )
        .await?;
        tx.commit().await.map_err(fail)?;
        Ok(CorrectionReceipt {
            operation_id: command.operation_id.clone(),
            workout_ids: affected,
        })
    }
}

fn validate_command(c: &WorkoutCorrection, domain: SessionDomain) -> StorageResult<()> {
    if c.operation_id.len() < 8
        || c.operation_id.len() > 128
        || !c
            .operation_id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    {
        return Err(invalid(
            "Invalid save request. Reopen the editor and try again.",
        ));
    }
    if c.targets.len() > MAX_COMMAND_TARGETS || c.intervals.len() > 2 {
        return Err(invalid("Choose at most two output workouts."));
    }
    let unique: std::collections::HashSet<_> = c.targets.iter().map(|t| t.id).collect();
    if unique.len() != c.targets.len() {
        return Err(invalid("Choose each workout only once."));
    }
    for w in &c.intervals {
        if !domain.valid_kind(&w.kind) {
            return Err(invalid("Choose a valid recording type."));
        }
        if w.start_ts >= w.end_ts || w.end_ts - w.start_ts > Duration::hours(MAX_WORKOUT_HOURS) {
            return Err(invalid("Choose an end after the start, within 24 hours."));
        }
        if w.end_ts > Utc::now() {
            return Err(invalid("Choose a recording that has already finished."));
        }
    }
    Ok(())
}
fn validate_shape(c: &WorkoutCorrection, before: &[WorkoutSession]) -> StorageResult<()> {
    let valid = match c.action.as_str() {
        "add" => before.is_empty() && c.intervals.len() == 1,
        "edit" | "label" => before.len() == 1 && c.intervals.len() == 1,
        "remove" => before.len() == 1 && c.intervals.is_empty(),
        "merge" => {
            before.len() >= 2
                && c.intervals.len() == 1
                && c.intervals[0].start_ts == before[0].start_ts
                && Some(c.intervals[0].end_ts) == before.iter().map(|w| w.end_ts).max()
        }
        "split" => {
            before.len() == 1
                && c.intervals.len() == 2
                && c.intervals[0].start_ts == before[0].start_ts
                && c.intervals[0].end_ts == c.intervals[1].start_ts
                && c.intervals[1].end_ts == before[0].end_ts
        }
        _ => false,
    };
    if !valid {
        return Err(invalid(
            "The selected workouts or times changed. Reopen the editor and try again.",
        ));
    }
    if c.action == "label"
        && (c.intervals[0].start_ts != before[0].start_ts
            || c.intervals[0].end_ts != before[0].end_ts)
    {
        return Err(invalid(
            "Changing a type cannot change the recording times.",
        ));
    }
    Ok(())
}

async fn undo(
    tx: &mut PgConnection,
    domain: SessionDomain,
    device: &str,
    c: &WorkoutCorrection,
    payload: Value,
    version: i32,
) -> StorageResult<CorrectionReceipt> {
    if !c.targets.is_empty() || !c.intervals.is_empty() {
        return Err(invalid("Undo cannot include new recording times."));
    }
    let id = c
        .undo_id
        .as_deref()
        .ok_or_else(|| invalid("Choose the change to undo."))?;
    let (snapshot,affected,active):(Value,Vec<i64>,bool)=sqlx::query_as(&sql(domain, "SELECT before_state,affected_ids,active FROM workout_corrections WHERE device_id=$1 AND operation_id=$2"))
        .bind(device).bind(id).fetch_optional(&mut *tx).await.map_err(fail)?.ok_or(StorageError::CorrectionNotFound)?;
    if !active {
        return Err(conflict(
            "This change has already been undone. Refresh the recordings.",
        ));
    }
    let before: Vec<WorkoutSession> = serde_json::from_value(snapshot)
        .map_err(|e| StorageError::unavailable(StoreOperation::CorrectWorkout, e))?;
    let current: Vec<WorkoutSession> = sqlx::query_as(&sql(
        domain,
        &format!("{SELECT} WHERE device_id=$1 AND id=ANY($2)"),
    ))
    .bind(device)
    .bind(&affected)
    .fetch_all(&mut *tx)
    .await
    .map_err(fail)?;
    if current.len() != affected.len() || current.iter().any(|w| w.last_edit.as_deref() != Some(id))
    {
        return Err(conflict(
            "A recording has been edited again. Undo its latest change first.",
        ));
    }
    let restored_ids: Vec<_> = before
        .iter()
        .filter(|w| w.status == "active")
        .map(|w| w.id)
        .collect();
    for row in before.iter().filter(|w| w.status == "active") {
        let overlap:bool=sqlx::query_scalar(&sql(domain, "SELECT EXISTS(SELECT 1 FROM workout_sessions WHERE device_id=$1 AND status='active' AND id<>ALL($4) AND start_ts<$3 AND end_ts>$2)"))
            .bind(device).bind(row.start_ts).bind(row.end_ts).bind(&affected).fetch_one(&mut *tx).await.map_err(fail)?;
        if overlap {
            return Err(conflict(
                "Another recording now overlaps these times. Adjust it before restoring this change.",
            ));
        }
    }
    if domain == SessionDomain::Sleep {
        for row in before
            .iter()
            .filter(|r| r.fixed && r.status == "active" && r.kind == "main")
        {
            check_main(
                tx,
                device,
                &[crate::SessionInterval {
                    start_ts: row.start_ts,
                    end_ts: row.end_ts,
                    kind: row.kind.clone(),
                }],
                &affected,
                &row.timezone,
            )
            .await?;
        }
    }
    for row in &current {
        let mut restored = before
            .iter()
            .find(|w| w.id == row.id)
            .cloned()
            .unwrap_or_else(|| {
                let mut hidden = row.clone();
                hidden.status = "superseded".to_owned();
                hidden.last_edit = None;
                hidden.replacements = restored_ids.clone();
                hidden
            });
        restored.revision = row.revision + 1;
        restored.notification_eligible = false;
        restored.metrics_pending = restored.status == "active";
        restored.metrics = Json(SessionMetrics::default());
        persist(tx, domain, device, &restored).await?;
    }
    sqlx::query(&sql(
        domain,
        "UPDATE workout_corrections SET active=false WHERE operation_id=$1",
    ))
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(fail)?;
    sqlx::query(&sql(domain, "INSERT INTO workout_corrections(operation_id,device_id,request,before_state,affected_ids,active) VALUES($1,$2,$3,$4,$5,false)"))
        .bind(&c.operation_id).bind(device).bind(payload).bind(json!(current)).bind(&affected).execute(&mut *tx).await.map_err(fail)?;
    let from = current
        .iter()
        .chain(&before)
        .map(|w| w.start_ts)
        .min()
        .ok_or_else(|| invalid("No workout to restore."))?;
    let to = current
        .iter()
        .chain(&before)
        .map(|w| w.end_ts)
        .max()
        .ok_or_else(|| invalid("No workout to restore."))?;
    let tz: String = sqlx::query_scalar(&sql(
        domain,
        "SELECT coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC')",
    ))
    .bind(device)
    .fetch_one(&mut *tx)
    .await
    .map_err(fail)?;
    invalidate(tx, domain, device, from, to, &tz, version).await?;
    Ok(CorrectionReceipt {
        operation_id: c.operation_id.clone(),
        workout_ids: affected,
    })
}

pub(crate) async fn invalidate(
    tx: &mut PgConnection,
    domain: SessionDomain,
    device: &str,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    tz: &str,
    version: i32,
) -> StorageResult<()> {
    // Calendar arithmetic is in Postgres, including 23/25-hour days. Adjacent dates
    // cover detector context; every actual interval date is also invalidated.
    sqlx::query(&sql(domain, "INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,backfill)
        SELECT $1,'__kind__',d::date,$4,$5,true FROM generate_series(($2 AT TIME ZONE $4)::date-1,($3 AT TIME ZONE $4)::date+1,interval '1 day') d
        ON CONFLICT(device_id,kind,day,tz,algo_version) DO UPDATE SET generation=analysis_jobs.generation+1,available_at=now(),backfill=true"))
        .bind(device).bind(from).bind(to).bind(tz).bind(version).execute(tx).await.map_err(fail)?;
    Ok(())
}

pub(crate) async fn persist(
    tx: &mut PgConnection,
    domain: SessionDomain,
    device: &str,
    w: &WorkoutSession,
) -> StorageResult<()> {
    sqlx::query(&sql(domain, "INSERT INTO workout_sessions(id,device_id,start_ts,end_ts,kind,detected_kind,edited,fixed,auto_detected,notification_eligible,revision,status,last_edit,replacements,metrics,metrics_pending,timezone)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
        ON CONFLICT(id) DO UPDATE SET start_ts=EXCLUDED.start_ts,end_ts=EXCLUDED.end_ts,kind=EXCLUDED.kind,detected_kind=EXCLUDED.detected_kind,edited=EXCLUDED.edited,fixed=EXCLUDED.fixed,auto_detected=EXCLUDED.auto_detected,notification_eligible=EXCLUDED.notification_eligible,revision=EXCLUDED.revision,status=EXCLUDED.status,last_edit=EXCLUDED.last_edit,replacements=EXCLUDED.replacements,metrics=EXCLUDED.metrics,metrics_pending=EXCLUDED.metrics_pending,timezone=EXCLUDED.timezone"))
        .bind(w.id).bind(device).bind(w.start_ts).bind(w.end_ts).bind(&w.kind).bind(&w.detected_kind).bind(w.edited).bind(w.fixed).bind(w.auto_detected).bind(w.notification_eligible).bind(w.revision).bind(&w.status).bind(&w.last_edit).bind(&w.replacements).bind(&w.metrics).bind(w.metrics_pending).bind(&w.timezone)
        .execute(tx).await.map_err(fail)?;
    Ok(())
}

/// Reconciles automatic identities by overlap across start shifts and version bumps,
/// then publishes fixed-window metrics. Caller holds the device and generation locks.
pub(crate) async fn publish_domain_sessions(
    tx: &mut PgConnection,
    domain: SessionDomain,
    job: &crate::AnalysisJob,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    calculated: &[SessionCalculation],
) -> StorageResult<()> {
    let mut existing:Vec<WorkoutSession>=sqlx::query_as(&sql(domain, &format!("{SELECT} WHERE device_id=$1 AND NOT fixed AND (status='active' OR last_edit IS NULL) AND status<>'removed' AND end_ts>$2 AND start_ts<$3 ORDER BY id")))
        .bind(&job.device_id).bind(from-Duration::hours(MAX_WORKOUT_HOURS)).bind(to+Duration::hours(MAX_WORKOUT_HOURS)).fetch_all(&mut *tx).await.map_err(fail)?;
    let mut used = std::collections::HashSet::new();
    for c in calculated {
        if let Some(id) = c.id {
            sqlx::query(&sql(domain, "UPDATE workout_sessions SET metrics=$3,metrics_pending=false WHERE device_id=$1 AND id=$2 AND fixed AND status='active'"))
                .bind(&job.device_id).bind(id).bind(Json(&c.metrics)).execute(&mut *tx).await.map_err(fail)?;
            continue;
        }
        let best = existing
            .iter()
            .filter(|w| !used.contains(&w.id))
            .filter_map(|w| {
                let overlap = (w.end_ts.min(c.end_ts) - w.start_ts.max(c.start_ts)).num_seconds();
                let shorter = (w.end_ts - w.start_ts)
                    .num_seconds()
                    .min((c.end_ts - c.start_ts).num_seconds());
                (overlap > 0 && overlap * 2 >= shorter).then_some((w, overlap))
            })
            .max_by_key(|(w, overlap)| (*overlap, std::cmp::Reverse(w.id)))
            .map(|(w, _)| w.clone());
        let mut row = if let Some(mut row) = best {
            let kind = if row.edited {
                row.kind.clone()
            } else {
                c.kind.clone()
            };
            if row.start_ts != c.start_ts
                || row.end_ts != c.end_ts
                || row.kind != kind
                || row.status != "active"
            {
                row.revision += 1;
            }
            row.start_ts = c.start_ts;
            row.end_ts = c.end_ts;
            row.kind = kind;
            row.detected_kind = c.kind.clone();
            row.status = "active".to_owned();
            row.auto_detected = true;
            row.replacements.clear();
            row
        } else {
            let id: i64 = sqlx::query_scalar(&sql(domain, "SELECT nextval('workouts_id_seq')"))
                .fetch_one(&mut *tx)
                .await
                .map_err(fail)?;
            WorkoutSession {
                id,
                start_ts: c.start_ts,
                end_ts: c.end_ts,
                duration_s: 0,
                kind: c.kind.clone(),
                detected_kind: c.kind.clone(),
                edited: false,
                fixed: false,
                auto_detected: true,
                notification_eligible: domain == SessionDomain::Workout
                    && !job.backfill
                    && c.end_ts > Utc::now() - Duration::hours(24),
                revision: 1,
                status: "active".to_owned(),
                last_edit: None,
                replacements: vec![],
                metrics: Json(SessionMetrics::default()),
                metrics_pending: false,
                timezone: job.tz.clone(),
            }
        };
        if job.backfill {
            row.notification_eligible = false;
        }
        row.metrics = Json(c.metrics.clone());
        row.metrics_pending = false;
        row.duration_s = (row.end_ts - row.start_ts).num_seconds();
        persist(tx, domain, &job.device_id, &row).await?;
        used.insert(row.id);
        // Late legacy notifications can still find the stable session after raw candidate ids change.
        if domain == SessionDomain::Workout {
            sqlx::query(&sql(domain, "INSERT INTO workout_aliases(legacy_id,session_id) SELECT id,$3 FROM workouts WHERE device_id=$1 AND start_ts=$2 ON CONFLICT(legacy_id) DO UPDATE SET session_id=EXCLUDED.session_id"))
            .bind(&job.device_id).bind(row.start_ts).bind(row.id).execute(&mut *tx).await.map_err(fail)?;
        }
    }
    for row in &mut existing {
        if row.status == "active"
            && if domain == SessionDomain::Sleep {
                row.end_ts >= from && row.end_ts < to
            } else {
                row.start_ts >= from && row.start_ts < to
            }
            && !used.contains(&row.id)
        {
            row.status = "superseded".to_owned();
            row.notification_eligible = false;
            row.revision += 1;
            persist(tx, domain, &job.device_id, row).await?;
        }
    }
    Ok(())
}

/// Maps only internal identifiers, never user-provided SQL.
pub(crate) fn sql(domain: SessionDomain, query: &str) -> String {
    query
        .replace("workout_sessions", domain.sessions())
        .replace("workout_corrections", domain.corrections())
        .replace("workout_aliases", domain.aliases())
        .replace("workouts_id_seq", domain.sequence())
        .replace("__kind__", domain.kind())
}
pub(crate) async fn check_main(
    tx: &mut PgConnection,
    device: &str,
    intervals: &[crate::SessionInterval],
    ids: &[i64],
    tz: &str,
) -> StorageResult<()> {
    for interval in intervals.iter().filter(|i| i.kind == "main") {
        let conflict: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sleep_sessions WHERE device_id=$1 AND status='active' AND fixed AND kind='main' AND id<>ALL($2) AND (end_ts AT TIME ZONE timezone)::date=($3 AT TIME ZONE $4)::date)")
            .bind(device).bind(ids).bind(interval.end_ts).bind(tz).fetch_one(&mut *tx).await.map_err(fail)?;
        if conflict {
            return Err(invalid(
                "There is already a main sleep for this day. Merge it or change its type first.",
            ));
        }
    }
    Ok(())
}
