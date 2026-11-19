//! Previewed, idempotent reset of manual intent. Resets archive their snapshots so
//! they can be undone; neither reset nor undo modifies any sensor record.
use chrono::{DateTime, Utc};
type CorrectionBounds = (String, DateTime<Utc>, DateTime<Utc>, Vec<i64>);
use crate::session_store::{
    SELECT, conflict, fail, invalid, invalidate, lock_device, persist, sql,
};
use crate::{
    AnalysisVersions, PostgresStore, SessionDomain, StorageError, StorageResult, WorkoutSession,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::PgConnection;

/// Scope is either a recording, a half-open date range, or all recorded history.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResetScope {
    pub domains: Vec<SessionDomain>,
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
    pub target_id: Option<i64>,
}
/// The fingerprint prevents a stale confirmation from discarding newer edits.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResetCommand {
    pub operation_id: String,
    pub scope: ResetScope,
    pub token: String,
}
/// Exact expanded scope, including the complete history of connected merges/splits.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResetPreview {
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    pub manual_changes: usize,
    pub token: String,
    pub expanded: bool,
}
/// Durable receipt; an identical retry returns this result even after recalculation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResetReceipt {
    pub operation_id: String,
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
}
/// Idempotent undo of a reset, distinct from undo of one ordinary correction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoReset {
    pub operation_id: String,
    pub reset_id: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Snapshot {
    domain: SessionDomain,
    sessions: Vec<WorkoutSession>,
    commands: Vec<String>,
}

impl PostgresStore {
    /// Recent reversible resets, without exposing correction snapshots.
    /// # Errors
    /// Storage failure.
    pub async fn reset_history(&self, device: &str) -> StorageResult<Vec<Value>> {
        sqlx::query_scalar("SELECT jsonb_build_object('operation_id',operation_id,'from',scope_start,'to',scope_end,'domains',request->'scope'->'domains') FROM analysis_resets WHERE device_id=$1 AND active ORDER BY created_at DESC LIMIT 20")
   .bind(device).fetch_all(self.pool()).await.map_err(fail)
    }

    /// Resolves reset scope without changing user intent.
    /// # Errors
    /// Invalid scope, missing recording, or storage failure.
    pub async fn preview_reset(
        &self,
        device: &str,
        scope: &ResetScope,
    ) -> StorageResult<ResetPreview> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        lock_device(&mut tx, device).await?;
        let (preview, _) = resolve(&mut tx, device, scope).await?;
        tx.commit().await.map_err(fail)?;
        Ok(preview)
    }
    /// Retires manual overrides and queues rederivation in one transaction.
    /// # Errors
    /// Stale preview, reused command, or storage failure. All changes roll back together.
    pub async fn reset_analysis(
        &self,
        device: &str,
        command: &ResetCommand,
        versions: AnalysisVersions,
    ) -> StorageResult<ResetReceipt> {
        validate_id(&command.operation_id)?;
        let payload = json!(command);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        lock_device(&mut tx, device).await?;
        if let Some(receipt) = existing(&mut tx, device, &command.operation_id, &payload).await? {
            return Ok(receipt);
        }
        let (preview, snapshots) = resolve(&mut tx, device, &command.scope).await?;
        if preview.token != command.token {
            return Err(conflict(
                "These recordings changed. Review the reset again.",
            ));
        }
        let tz = zone(&mut tx, device).await?;
        for snapshot in &snapshots {
            for row in &snapshot.sessions {
                let mut reset = row.clone();
                reset.fixed = false;
                reset.edited = false;
                reset.last_edit = None;
                reset.replacements.clear();
                reset.revision += 1;
                reset.notification_eligible = false;
                reset.metrics_pending = reset.status == "active";
                if reset.status == "removed" {
                    reset.status = "superseded".into();
                }
                persist(&mut tx, snapshot.domain, device, &reset).await?;
            }
            sqlx::query(&sql(snapshot.domain,"UPDATE workout_corrections SET active=false WHERE device_id=$1 AND operation_id=ANY($2)"))
    .bind(device).bind(&snapshot.commands).execute(&mut *tx).await.map_err(fail)?;
            invalidate(
                &mut tx,
                snapshot.domain,
                device,
                preview.from,
                preview.to,
                &tz,
                version(snapshot.domain, versions),
            )
            .await?;
        }
        sqlx::query("INSERT INTO analysis_resets(operation_id,device_id,request,snapshot,scope_start,scope_end) VALUES($1,$2,$3,$4,$5,$6)")
   .bind(&command.operation_id).bind(device).bind(payload).bind(json!(snapshots)).bind(preview.from).bind(preview.to).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(ResetReceipt {
            operation_id: command.operation_id.clone(),
            from: preview.from,
            to: preview.to,
        })
    }
    /// Restores the pre-reset choices, then derives metrics using current recordings.
    /// # Errors
    /// A later overlapping manual edit/reset must be undone first; automatic work is safe.
    pub async fn undo_reset(
        &self,
        device: &str,
        command: &UndoReset,
        versions: AnalysisVersions,
    ) -> StorageResult<ResetReceipt> {
        validate_id(&command.operation_id)?;
        let payload = json!(command);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        lock_device(&mut tx, device).await?;
        if let Some(receipt) = existing(&mut tx, device, &command.operation_id, &payload).await? {
            return Ok(receipt);
        }
        let (saved,from,to,active,created):(Value,DateTime<Utc>,DateTime<Utc>,bool,DateTime<Utc>)=sqlx::query_as("SELECT snapshot,scope_start,scope_end,active,created_at FROM analysis_resets WHERE device_id=$1 AND operation_id=$2")
    .bind(device).bind(&command.reset_id).fetch_optional(&mut *tx).await.map_err(fail)?.ok_or(StorageError::CorrectionNotFound)?;
        if !active {
            return Err(conflict("This reset has already been undone."));
        }
        let snapshots: Vec<Snapshot> = serde_json::from_value(saved)
            .map_err(|e| StorageError::unavailable(crate::StoreOperation::Analysis, e))?;
        let domains: Vec<_> = snapshots.iter().map(|s| s.domain.kind()).collect();
        let later:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM analysis_resets WHERE device_id=$1 AND active AND created_at>$2 AND scope_start<$4 AND scope_end>$3 AND request->'scope'->'domains' ?| $5)")
    .bind(device).bind(created).bind(from).bind(to).bind(&domains).fetch_one(&mut *tx).await.map_err(fail)?;
        if later {
            return Err(conflict("Undo the newer reset first."));
        }
        let tz = zone(&mut tx, device).await?;
        for snapshot in snapshots {
            let later:bool=sqlx::query_scalar(&sql(snapshot.domain,"SELECT EXISTS(SELECT 1 FROM workout_corrections WHERE device_id=$1 AND active AND created_at>$2 AND scope_start<$4 AND scope_end>$3)"))
     .bind(device).bind(created).bind(from).bind(to).fetch_one(&mut *tx).await.map_err(fail)?;
            if later {
                return Err(conflict(
                    "A recording has been edited since this reset. Undo that edit first.",
                ));
            }
            let current: Vec<WorkoutSession> = sqlx::query_as(&sql(
                snapshot.domain,
                &format!("{SELECT} WHERE device_id=$1 AND end_ts>$2 AND start_ts<$3"),
            ))
            .bind(device)
            .bind(from)
            .bind(to)
            .fetch_all(&mut *tx)
            .await
            .map_err(fail)?;
            let a = current
                .iter()
                .map(|r| r.start_ts)
                .min()
                .unwrap_or(from)
                .min(from);
            let b = current.iter().map(|r| r.end_ts).max().unwrap_or(to).max(to);
            for row in &current {
                if !snapshot.sessions.iter().any(|r| r.id == row.id) {
                    let mut retired = row.clone();
                    retired.status = "superseded".into();
                    retired.last_edit = Some(command.operation_id.clone());
                    retired.notification_eligible = false;
                    retired.revision += 1;
                    persist(&mut tx, snapshot.domain, device, &retired).await?;
                }
            }
            if snapshot.domain == SessionDomain::Sleep {
                let ids: Vec<_> = current.iter().map(|r| r.id).collect();
                for row in snapshot
                    .sessions
                    .iter()
                    .filter(|r| r.fixed && r.status == "active" && r.kind == "main")
                {
                    crate::session_store::check_main(
                        &mut tx,
                        device,
                        &[crate::SessionInterval {
                            start_ts: row.start_ts,
                            end_ts: row.end_ts,
                            kind: row.kind.clone(),
                        }],
                        &ids,
                        &row.timezone,
                    )
                    .await?;
                }
            }
            for mut restored in snapshot.sessions {
                let revision = current
                    .iter()
                    .find(|r| r.id == restored.id)
                    .map_or(restored.revision, |r| r.revision);
                restored.revision = revision + 1;
                restored.notification_eligible = false;
                restored.metrics_pending = restored.status == "active";
                persist(&mut tx, snapshot.domain, device, &restored).await?;
            }
            sqlx::query(&sql(snapshot.domain,"UPDATE workout_corrections SET active=true WHERE device_id=$1 AND operation_id=ANY($2)"))
     .bind(device).bind(&snapshot.commands).execute(&mut *tx).await.map_err(fail)?;
            invalidate(
                &mut tx,
                snapshot.domain,
                device,
                a,
                b,
                &tz,
                version(snapshot.domain, versions),
            )
            .await?;
        }
        sqlx::query("UPDATE analysis_resets SET active=false WHERE operation_id=$1")
            .bind(&command.reset_id)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        sqlx::query("INSERT INTO analysis_resets(operation_id,device_id,request,snapshot,scope_start,scope_end,active) VALUES($1,$2,$3,'[]',$4,$5,false)")
    .bind(&command.operation_id).bind(device).bind(payload).bind(from).bind(to).execute(&mut *tx).await.map_err(fail)?;
        tx.commit().await.map_err(fail)?;
        Ok(ResetReceipt {
            operation_id: command.operation_id.clone(),
            from,
            to,
        })
    }
}
fn version(domain: SessionDomain, v: AnalysisVersions) -> i32 {
    match domain {
        SessionDomain::Workout => v.workout,
        SessionDomain::Sleep => v.sleep,
    }
}
fn validate_id(id: &str) -> StorageResult<()> {
    if id.len() < 8 || id.len() > 128 || !id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
    {
        Err(invalid("Invalid reset request. Reopen the reset screen."))
    } else {
        Ok(())
    }
}
async fn zone(tx: &mut PgConnection, device: &str) -> StorageResult<String> {
    sqlx::query_scalar("SELECT coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC')")
        .bind(device)
        .fetch_one(tx)
        .await
        .map_err(fail)
}
async fn existing(
    tx: &mut PgConnection,
    device: &str,
    id: &str,
    payload: &Value,
) -> StorageResult<Option<ResetReceipt>> {
    let row: Option<(String, Value, DateTime<Utc>, DateTime<Utc>)> = sqlx::query_as(
        "SELECT device_id,request,scope_start,scope_end FROM analysis_resets WHERE operation_id=$1",
    )
    .bind(id)
    .fetch_optional(tx)
    .await
    .map_err(fail)?;
    row.map(|(owner, p, a, b)| {
        if owner != device || p != *payload {
            Err(conflict(
                "This reset request has already been used. Reopen the reset screen.",
            ))
        } else {
            Ok(ResetReceipt {
                operation_id: id.into(),
                from: a,
                to: b,
            })
        }
    })
    .transpose()
}
async fn resolve(
    tx: &mut PgConnection,
    device: &str,
    scope: &ResetScope,
) -> StorageResult<(ResetPreview, Vec<Snapshot>)> {
    if scope.domains.is_empty()
        || scope.domains.len() > 2
        || (scope.domains.len() == 2 && scope.domains[0] == scope.domains[1])
    {
        return Err(invalid("Choose Sleep, Workouts, or Both."));
    }
    if scope.from.is_some() != scope.to.is_some()
        || scope.target_id.is_some() && (scope.domains.len() != 1 || scope.from.is_some())
    {
        return Err(invalid("Choose a recording or date range."));
    }
    let (mut from, mut to) = if let Some(id) = scope.target_id {
        sqlx::query_as(&sql(
            scope.domains[0],
            "SELECT start_ts,end_ts FROM workout_sessions WHERE device_id=$1 AND id=$2",
        ))
        .bind(device)
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?
        .ok_or(StorageError::CorrectionNotFound)?
    } else if let Some((a, b)) = scope.from.zip(scope.to) {
        (a, b)
    } else {
        let (a, b): (Option<DateTime<Utc>>, Option<DateTime<Utc>>) = sqlx::query_as(
            "SELECT min(ts),max(ts)+interval '1 second' FROM samples WHERE device_id=$1",
        )
        .bind(device)
        .fetch_one(&mut *tx)
        .await
        .map_err(fail)?;
        a.zip(b)
            .ok_or_else(|| invalid("No recorded data yet. Sync your WHOOP first."))?
    };
    if from >= to {
        return Err(invalid("Choose an end date after the start."));
    }
    let original = (from, to);
    let (first, last): (Option<DateTime<Utc>>, Option<DateTime<Utc>>) = sqlx::query_as(
        "SELECT min(ts),max(ts)+interval '1 second' FROM samples WHERE device_id=$1",
    )
    .bind(device)
    .fetch_one(&mut *tx)
    .await
    .map_err(fail)?;
    let (first, last) = first
        .zip(last)
        .ok_or_else(|| invalid("No recorded data yet. Sync your WHOOP first."))?;
    if scope.target_id.is_none() {
        from = from.max(first);
        to = to.min(last);
    }
    if from >= to {
        return Err(invalid(
            "No strap data in this date range. Choose another range.",
        ));
    }
    let mut all = Vec::new();
    for &domain in &scope.domains {
        let commands:Vec<CorrectionBounds>=sqlx::query_as(&sql(domain,"SELECT operation_id,scope_start,scope_end,affected_ids FROM workout_corrections WHERE device_id=$1 AND active AND scope_start IS NOT NULL ORDER BY created_at,operation_id"))
   .bind(device).fetch_all(&mut *tx).await.map_err(fail)?;
        all.push((domain, commands));
    }
    // Expand to a fixed point: even a chain that moved a recording across dates resets as a unit.
    loop {
        let before = (from, to);
        for (_, commands) in &all {
            for (_, a, b, _) in commands {
                if *a < to && *b > from {
                    from = from.min(*a);
                    to = to.max(*b);
                }
            }
        }
        if before == (from, to) {
            break;
        }
    }
    let mut snapshots = Vec::new();
    let mut changes = 0;
    for (domain, commands) in all {
        let commands: Vec<_> = commands
            .into_iter()
            .filter(|(_, a, b, _)| *a < to && *b > from)
            .collect();
        let ids: Vec<_> = commands.iter().flat_map(|c| c.3.iter().copied()).collect();
        let sessions:Vec<WorkoutSession>=sqlx::query_as(&sql(domain,&format!("{SELECT} WHERE device_id=$1 AND ((end_ts>$2 AND start_ts<$3) OR id=ANY($4)) ORDER BY id")))
    .bind(device).bind(from).bind(to).bind(&ids).fetch_all(&mut *tx).await.map_err(fail)?;
        changes += commands.len();
        snapshots.push(Snapshot {
            domain,
            sessions,
            commands: commands.into_iter().map(|c| c.0).collect(),
        });
    }
    let fingerprint = json!([
        from,
        to,
        snapshots
            .iter()
            .map(|s| json!([
                s.domain,
                s.commands,
                s.sessions
                    .iter()
                    .map(|r| json!([
                        r.id,
                        r.revision,
                        r.start_ts,
                        r.end_ts,
                        r.status,
                        r.kind,
                        r.fixed,
                        r.last_edit
                    ]))
                    .collect::<Vec<_>>()
            ]))
            .collect::<Vec<_>>()
    ]);
    let token: String = sqlx::query_scalar("SELECT md5($1)")
        .bind(fingerprint.to_string())
        .fetch_one(&mut *tx)
        .await
        .map_err(fail)?;
    Ok((
        ResetPreview {
            from,
            to,
            manual_changes: changes,
            token,
            expanded: from < original.0 || to > original.1,
        },
        snapshots,
    ))
}
