//! Behavioural tests against isolated schemas: user intent survives durable worker
//! passes, failures, version changes and late readings. No personal fixtures.
#[path = "../../../tests/support/mod.rs"]
mod support;
use chrono::{DateTime, Duration, Utc};
use std::sync::atomic::{AtomicUsize, Ordering};
use support::{DEVICE, Db, at, day};
use zoop_analytics::WORKOUT_ALGO_VERSION as VERSION;
use zoop_core::HistoryWorker;
use zoop_storage::{
    DayPublication, SessionInterval, SessionRevision, WorkoutCorrection, WorkoutSession,
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn command(
    action: &str,
    targets: &[WorkoutSession],
    intervals: Vec<SessionInterval>,
) -> WorkoutCorrection {
    WorkoutCorrection {
        operation_id: format!("test-correction-{}", NEXT.fetch_add(1, Ordering::Relaxed)),
        action: action.into(),
        targets: targets
            .iter()
            .map(|w| SessionRevision {
                id: w.id,
                revision: w.revision,
            })
            .collect(),
        intervals,
        undo_id: None,
    }
}
fn interval(start: DateTime<Utc>, end: DateTime<Utc>) -> SessionInterval {
    SessionInterval {
        start_ts: start,
        end_ts: end,
        kind: "resistance".into(),
    }
}
async fn drain(db: &Db) {
    let worker = HistoryWorker::new(db.store.clone(), true, std::time::Duration::from_secs(60));
    for _ in 0..50 {
        if !worker.pass().await.unwrap() {
            return;
        }
    }
    panic!("jobs did not settle");
}
async fn sessions(db: &Db) -> Vec<WorkoutSession> {
    let mut rows = db
        .store
        .list_sessions(DEVICE, "active", None, None, 100)
        .await
        .unwrap();
    rows.sort_by_key(|w| w.start_ts);
    rows
}
async fn fixture() -> Db {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO profiles(device_id,sex,birth_year,weight_kg,tz) VALUES('TEST-RELIABILITY','male',1985,80,'UTC'); INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,'-infinity',to_jsonb(p) FROM profiles p;").await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-01-01T10:00:00Z'::timestamptz+make_interval(secs=>n),CASE WHEN n<1500 OR n>=2700 THEN 140 ELSE 75 END,ARRAY[500],0,0,0,$2 FROM generate_series(0,4499)n")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.store
        .seed_history(HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(sessions(&db).await.len(), 2);
    db
}
async fn undo(db: &Db, id: &str) {
    let mut c = command("undo", &[], vec![]);
    c.undo_id = Some(id.to_owned());
    db.store.correct_workout(DEVICE, &c, VERSION).await.unwrap();
    drain(db).await;
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn merge_split_trim_remove_and_nested_undo_survive_recalculation() {
    let db = fixture().await;
    let original = sessions(&db).await;
    let original_ids: Vec<_> = original.iter().map(|w| w.id).collect();
    let day_load = db
        .store
        .list_days(DEVICE, "UTC", 10, VERSION)
        .await
        .unwrap()[0]
        .load;
    let merge = command(
        "merge",
        &original,
        vec![interval(original[0].start_ts, original[1].end_ts)],
    );
    db.store
        .correct_workout(DEVICE, &merge, VERSION)
        .await
        .unwrap();
    let pending = sessions(&db).await;
    assert_eq!(pending.len(), 1);
    assert!(pending[0].metrics_pending);
    assert!(pending[0].metrics.load.is_none());
    drain(&db).await;
    let merged = sessions(&db).await;
    assert_eq!(merged[0].duration_s, 4500);
    assert_eq!(merged[0].metrics.coverage_s, Some(4500));
    assert!(!merged[0].metrics_pending);
    assert!(!merged[0].notification_eligible);
    assert_eq!(
        db.store
            .list_days(DEVICE, "UTC", 10, VERSION)
            .await
            .unwrap()[0]
            .load,
        day_load
    );
    let split = command(
        "split",
        &merged,
        vec![
            interval(merged[0].start_ts, at("2025-01-01T10:35:00Z")),
            interval(at("2025-01-01T10:35:00Z"), merged[0].end_ts),
        ],
    );
    db.store
        .correct_workout(DEVICE, &split, VERSION)
        .await
        .unwrap();
    drain(&db).await;
    let children = sessions(&db).await;
    assert_eq!(children.len(), 2);
    assert_eq!(
        children
            .iter()
            .map(|w| w.metrics.coverage_s.unwrap())
            .sum::<i64>(),
        4500
    );
    assert!(
        (children
            .iter()
            .map(|w| w.metrics.trimp.unwrap())
            .sum::<f64>()
            - merged[0].metrics.trimp.unwrap())
        .abs()
            < 1e-6
    );
    let edit = command(
        "edit",
        &children[..1],
        vec![interval(
            at("2025-01-01T10:05:00Z"),
            at("2025-01-01T10:30:00Z"),
        )],
    );
    db.store
        .correct_workout(DEVICE, &edit, VERSION)
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(
        sessions(&db).await.len(),
        2,
        "trimmed original cannot return"
    );
    let edited = sessions(&db).await;
    let remove = command("remove", &edited[..1], vec![]);
    db.store
        .correct_workout(DEVICE, &remove, VERSION)
        .await
        .unwrap();
    drain(&db).await;
    db.store
        .request_analysis(DEVICE, "workout", day("2025-01-01"), "UTC", VERSION, true)
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(sessions(&db).await.len(), 1);
    assert_eq!(
        db.store
            .list_sessions(DEVICE, "removed", None, None, 10)
            .await
            .unwrap()
            .len(),
        1
    );
    undo(&db, &remove.operation_id).await;
    undo(&db, &edit.operation_id).await;
    undo(&db, &split.operation_id).await;
    undo(&db, &merge.operation_id).await;
    assert_eq!(
        sessions(&db).await.iter().map(|w| w.id).collect::<Vec<_>>(),
        original_ids
    );
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn adds_require_samples_and_retries_conflicts_and_stale_forms_are_safe() {
    let db = fixture().await;
    let missing = command(
        "add",
        &[],
        vec![interval(
            at("2025-01-02T10:00:00Z"),
            at("2025-01-02T11:00:00Z"),
        )],
    );
    assert!(matches!(
        db.store.correct_workout(DEVICE, &missing, VERSION).await,
        Err(zoop_storage::StorageError::InvalidCorrection(_))
    ));
    assert_eq!(
        db.count("SELECT count(*) FROM workout_corrections").await,
        0
    );
    let add = command(
        "add",
        &[],
        vec![interval(
            at("2025-01-01T10:30:00Z"),
            at("2025-01-01T10:35:00Z"),
        )],
    );
    let a = db
        .store
        .correct_workout(DEVICE, &add, VERSION)
        .await
        .unwrap();
    let b = db
        .store
        .correct_workout(DEVICE, &add, VERSION)
        .await
        .unwrap();
    assert_eq!(a.workout_ids, b.workout_ids);
    let mut changed = add.clone();
    changed.intervals[0].end_ts += Duration::minutes(1);
    assert!(matches!(
        db.store.correct_workout(DEVICE, &changed, VERSION).await,
        Err(zoop_storage::StorageError::CorrectionConflict(_))
    ));
    drain(&db).await;
    let rows = sessions(&db).await;
    assert_eq!(rows.len(), 3);
    assert_eq!(rows[1].duration_s, 300);
    let overlap = command("add", &[], vec![interval(rows[0].start_ts, rows[0].end_ts)]);
    assert!(matches!(
        db.store.correct_workout(DEVICE, &overlap, VERSION).await,
        Err(zoop_storage::StorageError::CorrectionConflict(_))
    ));
    let edit = command(
        "edit",
        &rows[1..2],
        vec![interval(
            rows[1].start_ts,
            rows[1].end_ts - Duration::minutes(1),
        )],
    );
    db.store
        .correct_workout(DEVICE, &edit, VERSION)
        .await
        .unwrap();
    let stale = command("remove", &rows[1..2], vec![]);
    assert!(matches!(
        db.store.correct_workout(DEVICE, &stale, VERSION).await,
        Err(zoop_storage::StorageError::CorrectionConflict(_))
    ));
    // A bare raw frame without decoded sensor readings is not enough to add a workout.
    assert_eq!(
        db.count("SELECT count(*) FROM workout_corrections").await,
        2
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn edit_fences_inflight_worker_and_version_changes_keep_identity_and_intent() {
    let db = fixture().await;
    let rows = sessions(&db).await;
    db.store
        .request_analysis(DEVICE, "workout", day("2025-01-01"), "UTC", VERSION, true)
        .await
        .unwrap();
    let job = db
        .store
        .claim_analysis(HistoryWorker::versions())
        .await
        .unwrap()
        .unwrap();
    let edit = command(
        "edit",
        &rows[..1],
        vec![interval(
            rows[0].start_ts + Duration::minutes(3),
            rows[0].end_ts,
        )],
    );
    db.store
        .correct_workout(DEVICE, &edit, VERSION)
        .await
        .unwrap();
    assert!(
        !db.store
            .publish_day_sessions(
                &job,
                DayPublication {
                    from: at("2025-01-01T00:00:00Z"),
                    to: at("2025-01-02T00:00:00Z"),
                    workouts: &[],
                    strain: None,
                    inputs: serde_json::json!({}),
                    sessions: Some(&[])
                }
            )
            .await
            .unwrap()
    );
    drain(&db).await;
    assert_eq!(sessions(&db).await[0].start_ts, edit.intervals[0].start_ts);
    // Late readings shift the raw candidate earlier. Its trimmed minute stays hidden.
    let raw = db.raw(2).await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-01-01T09:59:00Z'::timestamptz+make_interval(secs=>n),140,ARRAY[500],0,0,0,$2 FROM generate_series(0,59)n")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.store
        .request_analysis(DEVICE, "workout", day("2025-01-01"), "UTC", VERSION, true)
        .await
        .unwrap();
    drain(&db).await;
    let corrected = sessions(&db).await;
    assert_eq!(corrected.len(), 2);
    assert_eq!(corrected[0].id, rows[0].id);
    assert_eq!(corrected[0].start_ts, edit.intervals[0].start_ts);
    let calculated = zoop_core::analyze_day(&db.store, DEVICE, Some(day("2025-01-01")))
        .await
        .unwrap()
        .unwrap();
    db.store
        .request_analysis(
            DEVICE,
            "workout",
            day("2025-01-01"),
            "UTC",
            VERSION + 1,
            true,
        )
        .await
        .unwrap();
    let job = db
        .store
        .claim_analysis(zoop_storage::AnalysisVersions {
            sleep: 2,
            workout: VERSION + 1,
        })
        .await
        .unwrap()
        .unwrap();
    db.store
        .publish_day_sessions(
            &job,
            DayPublication {
                from: at("2025-01-01T00:00:00Z"),
                to: at("2025-01-02T00:00:00Z"),
                workouts: &[],
                strain: None,
                inputs: serde_json::json!({}),
                sessions: Some(&calculated.sessions),
            },
        )
        .await
        .unwrap();
    assert_eq!(
        sessions(&db).await.iter().map(|w| w.id).collect::<Vec<_>>(),
        rows.iter().map(|w| w.id).collect::<Vec<_>>()
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn cross_midnight_calories_are_allocated_once_and_dst_uses_calendar_days() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO profiles(device_id,sex,birth_year,weight_kg,tz) VALUES('TEST-RELIABILITY','male',1985,80,'Europe/Berlin'); INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,'-infinity',to_jsonb(p) FROM profiles p;").await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-03-29T22:50:00Z'::timestamptz+make_interval(secs=>n),140,ARRAY[500],0,0,0,$2 FROM generate_series(0,1799)n")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.store
        .seed_history(HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    let rows = sessions(&db).await;
    assert_eq!(rows.len(), 1);
    let edit = command(
        "edit",
        &rows,
        vec![interval(rows[0].start_ts, rows[0].end_ts)],
    );
    db.store
        .correct_workout(DEVICE, &edit, VERSION)
        .await
        .unwrap();
    drain(&db).await;
    db.sql("INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,'2025-03-30T12:00:00Z',jsonb_set(to_jsonb(p),'{weight_kg}','120') FROM profiles p;").await;
    db.store
        .request_analysis(
            DEVICE,
            "workout",
            day("2025-03-30"),
            "Europe/Berlin",
            VERSION,
            true,
        )
        .await
        .unwrap();
    drain(&db).await;
    let (a, b) = db
        .store
        .local_day_bounds(day("2025-03-30"), "Europe/Berlin")
        .await
        .unwrap();
    assert_eq!((b - a).num_hours(), 23);
    let days = db
        .store
        .list_days(DEVICE, "Europe/Berlin", 10, VERSION)
        .await
        .unwrap();
    assert_eq!(days.len(), 2);
    let total = sessions(&db).await[0].metrics.kcal.unwrap();
    assert!((f64::from(days[0].kcal.unwrap() + days[1].kcal.unwrap()) - total).abs() < 0.001);
    assert!((days[1].kcal.unwrap() / days[0].kcal.unwrap() - 2.).abs() < 0.001);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn http_contract_returns_flat_metrics_readable_errors_and_tombstones() {
    use axum::{
        body::{Body, to_bytes},
        http::Request,
    };
    use secrecy::SecretString;
    use tower::ServiceExt;
    let db = fixture().await;
    let app = zoop_api::build_router(zoop_api::AppState::new(
        db.store.clone(),
        SecretString::from("test-token"),
    ));
    let url = format!("/v1/devices/{DEVICE}/workouts");
    assert_eq!(
        app.clone()
            .oneshot(Request::get(&url).body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status(),
        401
    );
    let response = app
        .clone()
        .oneshot(
            Request::get(&url)
                .header("authorization", "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), 1_000_000).await.unwrap()).unwrap();
    assert!(body[0]["load"].is_number());
    assert!(body[0]["revision"].is_number());
    assert!(body[0]["metrics"].is_null());
    let rows = sessions(&db).await;
    let remove = command("remove", &rows[..1], vec![]);
    let req = || {
        Request::post(format!("{url}/corrections"))
            .header("authorization", "Bearer test-token")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_vec(&remove).unwrap()))
            .unwrap()
    };
    let a = app.clone().oneshot(req()).await.unwrap();
    assert_eq!(a.status(), 200);
    let b = app.clone().oneshot(req()).await.unwrap();
    assert_eq!(b.status(), 200);
    assert_eq!(
        to_bytes(a.into_body(), 1_000_000).await.unwrap(),
        to_bytes(b.into_body(), 1_000_000).await.unwrap()
    );
    let response = app
        .clone()
        .oneshot(
            Request::get(format!("{url}/{}", rows[0].id))
                .header("authorization", "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), 1_000_000).await.unwrap()).unwrap();
    assert_eq!(body["status"], "removed");
    let stale = command("remove", &rows[..1], vec![]);
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("{url}/corrections"))
                .header("authorization", "Bearer test-token")
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&stale).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 409);
    let response = app
        .oneshot(
            Request::get(format!("{url}/99999999"))
                .header("authorization", "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 404);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn migration_promotes_legacy_labels_to_reversible_confirmed_sessions() {
    let db = fixture().await;
    let old = db.store.list_workouts(DEVICE, VERSION, 10).await.unwrap();
    db.store
        .upsert_label(DEVICE, old[0].start_ts, old[0].end_ts, "walk")
        .await
        .unwrap();
    // Only this test's disposable schema: recreate the new projection from legacy inputs.
    db.sql("DROP TABLE workout_aliases,workout_corrections,workout_sessions")
        .await;
    db.sql(include_str!(
        "../../../migrations/0007_workout_corrections.sql"
    ))
    .await;
    let migrated = db
        .store
        .list_sessions(DEVICE, "active", None, None, 10)
        .await
        .unwrap();
    let labelled = migrated.iter().find(|w| w.edited).unwrap();
    assert!(labelled.fixed);
    assert_eq!(labelled.kind, "walk");
    let id = labelled.id;
    let edit = labelled.last_edit.clone().unwrap();
    db.store
        .request_analysis(DEVICE, "workout", day("2025-01-01"), "UTC", VERSION, true)
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(
        db.store
            .get_session(DEVICE, id)
            .await
            .unwrap()
            .unwrap()
            .kind,
        "walk"
    );
    undo(&db, &edit).await;
    let restored = db.store.get_session(DEVICE, id).await.unwrap().unwrap();
    assert!(!restored.edited);
    assert_eq!(restored.kind, "resistance");
}
