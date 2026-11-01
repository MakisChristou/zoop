//! Session corrections and resets exercised through the durable worker on real Postgres.
#[path = "../../../tests/support/mod.rs"]
mod support;
use snoop_core::HistoryWorker;
use snoop_storage::{
    ResetCommand, ResetScope, SessionDomain as Domain, SessionInterval, SessionRevision, UndoReset,
    WorkoutCorrection, WorkoutSession,
};
use std::sync::atomic::{AtomicUsize, Ordering};
use support::{DEVICE, Db, at};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn id() -> String {
    format!("sleep-test-{}", NEXT.fetch_add(1, Ordering::Relaxed))
}
fn change(
    action: &str,
    rows: &[WorkoutSession],
    windows: Vec<SessionInterval>,
) -> WorkoutCorrection {
    WorkoutCorrection {
        operation_id: id(),
        action: action.into(),
        targets: rows
            .iter()
            .map(|r| SessionRevision {
                id: r.id,
                revision: r.revision,
            })
            .collect(),
        intervals: windows,
        undo_id: None,
    }
}
fn window(a: &str, b: &str, kind: &str) -> SessionInterval {
    SessionInterval {
        start_ts: at(a),
        end_ts: at(b),
        kind: kind.into(),
    }
}
async fn drain(db: &Db) {
    let worker = HistoryWorker::new(db.store.clone(), true, std::time::Duration::from_secs(60));
    for _ in 0..100 {
        if !worker.pass().await.unwrap() {
            return;
        }
    }
    panic!("jobs did not settle");
}
async fn records(db: &Db, d: Domain) -> Vec<WorkoutSession> {
    let mut r = db
        .store
        .sessions(d)
        .list_sessions(DEVICE, "active", None, None, 100)
        .await
        .unwrap();
    r.sort_by_key(|r| r.start_ts);
    r
}
async fn fixture(gap: bool) -> Db {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO profiles(device_id,sex,birth_year,weight_kg,tz) VALUES('TEST-RELIABILITY','male',1985,80,'UTC'); INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,'-infinity',to_jsonb(p) FROM profiles p;").await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-03-30T00:00:00Z'::timestamptz+make_interval(secs=>n),CASE WHEN n>=3600 AND n<6300 THEN 80 ELSE 50 END,ARRAY[1000],0,0,CASE WHEN n>=3600 AND n<6300 THEN 0 ELSE 2 END,$2 FROM generate_series(0,8999)n WHERE NOT $3 OR n<3600 OR n>=6300")
 .bind(DEVICE).bind(raw).bind(gap).execute(&db.pool).await.unwrap();
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1, '2025-03-30T14:00:00Z'::timestamptz+make_interval(secs=>n),50,ARRAY[1000],0,0,2,$2 FROM generate_series(0,1799)n UNION ALL SELECT $1,'2025-03-30T16:00:00Z'::timestamptz+make_interval(secs=>n),120,ARRAY[500],n*2,1,0,$2 FROM generate_series(0,1799)n")
 .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.store
        .seed_history(HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    db
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn merge_preserves_awake_break_and_naps_and_updates_all_readers() {
    let db = fixture(false).await;
    let before = records(&db, Domain::Sleep).await;
    assert_eq!(before.len(), 3, "afternoon nap is included");
    let c = change(
        "merge",
        &before[..2],
        vec![SessionInterval {
            start_ts: before[0].start_ts,
            end_ts: before[1].end_ts,
            kind: "main".into(),
        }],
    );
    let access = db.store.sessions(Domain::Sleep);
    access
        .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
        .await
        .unwrap();
    drain(&db).await;
    let merged = records(&db, Domain::Sleep).await;
    assert_eq!(merged.len(), 2);
    assert_eq!(merged[0].id, before[0].id);
    assert!(merged[0].fixed);
    let m = merged[0].metrics.sleep.as_ref().unwrap();
    assert_eq!(m["window"]["waso_s"], 2700);
    assert_eq!(m["unknown_s"], 0);
    let nights = db
        .store
        .list_sleeps(DEVICE, HistoryWorker::versions().sleep, 10)
        .await
        .unwrap();
    assert_eq!(nights.len(), 1);
    assert_eq!(nights[0].metrics["naps"].as_array().unwrap().len(), 1);
    let masks = db
        .store
        .sleep_windows(
            DEVICE,
            at("2025-03-30T00:00:00Z"),
            at("2025-03-31T00:00:00Z"),
        )
        .await
        .unwrap();
    assert!(
        !masks
            .iter()
            .any(|(a, b)| *a <= at("2025-03-30T01:30:00Z") && *b > at("2025-03-30T01:30:00Z")),
        "awake break stays awake for Load"
    );
    let raw: i64 = sqlx::query_scalar("SELECT count(*) FROM raw_frames")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    assert_eq!(raw, 1);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn missing_recordings_remain_gaps_and_reset_is_reversible_after_recompute() {
    let db = fixture(true).await;
    let before = records(&db, Domain::Sleep).await;
    let access = db.store.sessions(Domain::Sleep);
    let c = change(
        "merge",
        &before[..2],
        vec![SessionInterval {
            start_ts: before[0].start_ts,
            end_ts: before[1].end_ts,
            kind: "main".into(),
        }],
    );
    access
        .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
        .await
        .unwrap();
    drain(&db).await;
    let merged = records(&db, Domain::Sleep).await;
    let m = merged[0].metrics.sleep.as_ref().unwrap();
    assert_eq!(m["unknown_s"], 2700);
    assert!(m["efficiency"].is_null());
    for s in m["segments"].as_array().unwrap() {
        let a = chrono::DateTime::parse_from_rfc3339(s["start"].as_str().unwrap()).unwrap();
        let b = chrono::DateTime::parse_from_rfc3339(s["end"].as_str().unwrap()).unwrap();
        assert!(b <= at("2025-03-30T01:00:00Z") || a >= at("2025-03-30T01:45:00Z"));
    }
    let scope = ResetScope {
        domains: vec![Domain::Sleep],
        from: None,
        to: None,
        target_id: Some(merged[0].id),
    };
    let preview = db.store.preview_reset(DEVICE, &scope).await.unwrap();
    assert_eq!(preview.manual_changes, 1);
    let reset = ResetCommand {
        operation_id: id(),
        scope,
        token: preview.token,
    };
    let receipt = db
        .store
        .reset_analysis(DEVICE, &reset, HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(records(&db, Domain::Sleep).await.len(), 3);
    assert!(records(&db, Domain::Sleep).await.iter().all(|s| !s.edited));
    assert_eq!(
        db.store
            .reset_analysis(DEVICE, &reset, HistoryWorker::versions())
            .await
            .unwrap()
            .operation_id,
        receipt.operation_id
    );
    let undo = UndoReset {
        operation_id: id(),
        reset_id: receipt.operation_id,
    };
    db.store
        .undo_reset(DEVICE, &undo, HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    let restored = records(&db, Domain::Sleep).await;
    assert_eq!(restored.len(), 2);
    assert_eq!(restored[0].id, merged[0].id);
    assert!(restored[0].fixed);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn reset_both_retires_overrides_not_raw_data_and_rejects_stale_confirmations() {
    let db = fixture(false).await;
    let sleep = records(&db, Domain::Sleep).await;
    let workouts = records(&db, Domain::Workout).await;
    assert_eq!(workouts.len(), 1);
    let c = change(
        "edit",
        &workouts,
        vec![SessionInterval {
            start_ts: workouts[0].start_ts,
            end_ts: workouts[0].end_ts,
            kind: "resistance".into(),
        }],
    );
    db.store
        .correct_workout(DEVICE, &c, HistoryWorker::versions().workout)
        .await
        .unwrap();
    let scope = ResetScope {
        domains: vec![Domain::Sleep, Domain::Workout],
        from: None,
        to: None,
        target_id: None,
    };
    let preview = db.store.preview_reset(DEVICE, &scope).await.unwrap();
    let c = change("remove", &sleep[2..], vec![]);
    db.store
        .sessions(Domain::Sleep)
        .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
        .await
        .unwrap();
    let command = ResetCommand {
        operation_id: id(),
        scope: scope.clone(),
        token: preview.token,
    };
    assert!(
        db.store
            .reset_analysis(DEVICE, &command, HistoryWorker::versions())
            .await
            .is_err()
    );
    let before: String = sqlx::query_scalar(
        "SELECT md5(string_agg(encode(bytes,'hex'),'' ORDER BY id)) FROM raw_frames",
    )
    .fetch_one(&db.pool)
    .await
    .unwrap();
    let preview = db.store.preview_reset(DEVICE, &scope).await.unwrap();
    let command = ResetCommand {
        operation_id: id(),
        scope,
        token: preview.token,
    };
    db.store
        .reset_analysis(DEVICE, &command, HistoryWorker::versions())
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(records(&db, Domain::Sleep).await.len(), 3);
    assert_eq!(records(&db, Domain::Workout).await[0].kind, "walk");
    assert!(
        records(&db, Domain::Workout)
            .await
            .iter()
            .all(|s| !s.notification_eligible)
    );
    let after: String = sqlx::query_scalar(
        "SELECT md5(string_agg(encode(bytes,'hex'),'' ORDER BY id)) FROM raw_frames",
    )
    .fetch_one(&db.pool)
    .await
    .unwrap();
    assert_eq!(before, after);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn additions_require_data_and_midnight_edits_keep_identity_on_dst_days() {
    let db = fixture(false).await;
    let access = db.store.sessions(Domain::Sleep);
    let c = change(
        "add",
        &[],
        vec![window(
            "2025-03-29T12:00:00Z",
            "2025-03-29T13:00:00Z",
            "nap",
        )],
    );
    assert!(
        access
            .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
            .await
            .is_err()
    );
    let (from, to) = db
        .store
        .local_day_bounds(support::day("2025-03-30"), "Europe/Athens")
        .await
        .unwrap();
    assert_eq!((to - from).num_hours(), 23);
    let sleep = records(&db, Domain::Sleep).await;
    let c = change(
        "edit",
        &sleep[..1],
        vec![window(
            "2025-03-29T23:50:00Z",
            "2025-03-30T00:50:00Z",
            "main",
        )],
    );
    access
        .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
        .await
        .unwrap();
    drain(&db).await;
    let edited = access
        .get_session(DEVICE, sleep[0].id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(edited.start_ts, at("2025-03-29T23:50:00Z"));
    assert_eq!(edited.metrics.sleep.as_ref().unwrap()["unknown_s"], 600);
    let scope = ResetScope {
        domains: vec![Domain::Sleep],
        from: Some(at("2025-03-30T00:15:00Z")),
        to: Some(at("2025-03-30T00:30:00Z")),
        target_id: None,
    };
    assert!(
        db.store
            .preview_reset(DEVICE, &scope)
            .await
            .unwrap()
            .expanded
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sleep_edits_keep_fixed_workouts_and_removed_sleep_does_not_resurrect() {
    let db = fixture(false).await;
    let workouts = records(&db, Domain::Workout).await;
    let edit = change(
        "edit",
        &workouts,
        vec![SessionInterval {
            start_ts: workouts[0].start_ts,
            end_ts: workouts[0].end_ts,
            kind: "resistance".into(),
        }],
    );
    db.store
        .correct_workout(DEVICE, &edit, HistoryWorker::versions().workout)
        .await
        .unwrap();
    drain(&db).await;
    let fixed = records(&db, Domain::Workout).await.remove(0);
    let sleep = records(&db, Domain::Sleep).await;
    let access = db.store.sessions(Domain::Sleep);
    for row in &sleep {
        let c = change("remove", std::slice::from_ref(row), vec![]);
        access
            .correct_workout(DEVICE, &c, HistoryWorker::versions().sleep)
            .await
            .unwrap();
    }
    drain(&db).await;
    assert!(records(&db, Domain::Sleep).await.is_empty());
    assert!(
        db.store
            .list_sleeps(DEVICE, HistoryWorker::versions().sleep, 20)
            .await
            .unwrap()
            .is_empty(),
        "old candidates cannot resurrect a removed night"
    );
    let after = records(&db, Domain::Workout).await;
    let row = after.iter().find(|r| r.id == fixed.id).unwrap();
    assert_eq!(
        (row.start_ts, row.end_ts, row.kind.as_str()),
        (fixed.start_ts, fixed.end_ts, fixed.kind.as_str())
    );
    assert!(row.fixed);
    assert!(!row.notification_eligible);
}
