//! Read-only insight contracts, independent quality gates, and correction invalidation.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::Value;
use snoop_api::{AppState, build_router};
use snoop_core::{HistoryWorker, morning_insights};
use snoop_storage::{
    ResetCommand, ResetScope, SessionDomain, SessionInterval, SessionRevision, UndoReset,
    WorkoutCorrection,
};
use support::{DEVICE, Db, day};
use tower::ServiceExt;
async fn fixture() -> Db {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-01-01T06:00:00Z'::timestamptz+make_interval(days=>d,secs=>n),CASE WHEN n>=0 AND n<3600 THEN 55 ELSE 90 END,ARRAY[1000,1020],0,0,CASE WHEN n>=0 AND n<3600 THEN 2 ELSE 0 END,$2 FROM generate_series(0,19)d CROSS JOIN generate_series(-1800,5399)n")
 .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,metrics) SELECT 'TEST-RELIABILITY','2025-01-01T06:00:00Z'::timestamptz+make_interval(days=>d),'2025-01-01T07:00:00Z'::timestamptz+make_interval(days=>d),'main','main','UTC',jsonb_build_object('sleep',jsonb_build_object('window',jsonb_build_object('asleep_s',3600,'coverage_s',3600),'physiology',jsonb_build_object('resting_hr',55,'hrv_rmssd_ms',50,'hrv_windows',12))) FROM generate_series(0,19)d").await;
    db
}
async fn get(db: &Db, path: &str, auth: bool) -> (u16, Value) {
    let mut request = Request::get(path);
    if auth {
        request = request.header("authorization", "Bearer test-token");
    }
    let response = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(request.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status().as_u16();
    let body = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}
async fn brief(db: &Db) -> Value {
    serde_json::to_value(
        morning_insights(&db.store, DEVICE, day("2025-01-15"), "UTC")
            .await
            .unwrap()
            .unwrap(),
    )
    .unwrap()
}
async fn drain(db: &Db) {
    let worker = HistoryWorker::new(db.store.clone(), true, std::time::Duration::from_secs(60));
    for _ in 0..150 {
        if !worker.pass().await.unwrap() {
            return;
        }
    }
    panic!("jobs did not settle");
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn api_contract_dates_auth_and_no_future_leak() {
    let db = fixture().await;
    let path = format!("/v1/devices/{DEVICE}/days/2025-01-15/insights?tz=UTC");
    assert_eq!(get(&db, &path, false).await.0, 401);
    let (status, r) = get(&db, &path, true).await;
    assert_eq!(status, 200);
    assert_eq!(r["state"], "ready");
    assert_eq!(r["metrics"][0]["baseline"]["count"], 14);
    assert_eq!(r["metrics"][0]["baseline"]["average"], 3600.0);
    assert_eq!(r["metrics"][2]["quality"], "good");
    assert_eq!(r["metrics"][2]["week"]["count"], 7);
    assert_eq!(
        get(&db, &path.replace("tz=UTC", "tz=Invalid/Zone"), true)
            .await
            .0,
        400
    );
    assert_eq!(
        get(&db, &path.replace(DEVICE, "UNKNOWN"), true).await.0,
        404
    );
    assert_eq!(
        get(&db, &path.replace("2025-01-15", "not-a-date"), true)
            .await
            .0,
        400
    );
    db.sql("UPDATE sleep_sessions SET metrics=jsonb_set(metrics,'{sleep,window,asleep_s}','99999') WHERE end_ts>'2025-01-16'").await;
    assert_eq!(
        brief(&db).await["metrics"][0]["baseline"],
        r["metrics"][0]["baseline"]
    );
    // Group on the requested local date; the stored zone is retained for timing.
    let local = morning_insights(&db.store, DEVICE, day("2025-01-14"), "America/Los_Angeles")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(local.sleep_id, r["sleep_id"].as_i64());
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn partial_sleep_bad_hrv_and_interrupted_wake_are_separate() {
    let db = fixture().await;
    db.sql("UPDATE sleep_sessions SET metrics=jsonb_set(metrics,'{sleep,window,coverage_s}','3300') WHERE end_ts='2025-01-15T07:00:00Z'").await;
    let r = brief(&db).await;
    assert_eq!(r["metrics"][0]["quality"], "limited");
    assert_eq!(r["metrics"][1]["quality"], "good");
    db.sql("UPDATE sleep_sessions SET metrics=jsonb_set(metrics,'{sleep,physiology,hrv_windows}','1') WHERE end_ts='2025-01-15T07:00:00Z'").await;
    assert_eq!(brief(&db).await["metrics"][1]["quality"], "limited");
    db.sql("DELETE FROM samples WHERE ts>='2025-01-15T07:00:00Z' AND ts<'2025-01-15T07:30:00Z'")
        .await;
    assert_eq!(brief(&db).await["state"], "awaiting_sync");
    db.sql("UPDATE sleep_sessions SET fixed=true WHERE end_ts='2025-01-15T07:00:00Z'")
        .await;
    assert_eq!(
        brief(&db).await["state"],
        "ready",
        "user-confirmed bounds establish the end"
    );
    db.sql("DELETE FROM samples WHERE ts>='2025-01-14T05:55:00Z' AND ts<'2025-01-14T06:00:00Z'")
        .await;
    let truncated = morning_insights(&db.store, DEVICE, day("2025-01-14"), "UTC")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        truncated.state, "awaiting_sync",
        "a missing start is not a short night"
    );
    db.sql("UPDATE sleep_sessions SET metrics_pending=true WHERE end_ts='2025-01-15T07:00:00Z'")
        .await;
    assert_eq!(brief(&db).await["state"], "updating");
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn edits_reset_and_undo_refresh_brief_without_mutating_raw_data() {
    let db = fixture().await;
    let access = db.store.sessions(SessionDomain::Sleep);
    let rows = access
        .list_sessions(
            DEVICE,
            "active",
            Some(support::at("2025-01-15T00:00:00Z")),
            Some(support::at("2025-01-16T00:00:00Z")),
            10,
        )
        .await
        .unwrap();
    let row = &rows[0];
    let before = brief(&db).await;
    let change = WorkoutCorrection {
        operation_id: "insight-edit".into(),
        action: "edit".into(),
        targets: vec![SessionRevision {
            id: row.id,
            revision: row.revision,
        }],
        intervals: vec![SessionInterval {
            start_ts: row.start_ts,
            end_ts: row.end_ts - chrono::Duration::minutes(10),
            kind: "main".into(),
        }],
        undo_id: None,
    };
    access
        .correct_workout(DEVICE, &change, HistoryWorker::versions().sleep)
        .await
        .unwrap();
    assert_eq!(brief(&db).await["state"], "updating");
    drain(&db).await;
    let edited = brief(&db).await;
    assert_eq!(edited["metrics"][0]["value"], 3000.0);
    assert_ne!(edited["sleep_revision"], before["sleep_revision"]);
    let scope = ResetScope {
        domains: vec![SessionDomain::Sleep],
        from: None,
        to: None,
        target_id: Some(row.id),
    };
    let preview = db.store.preview_reset(DEVICE, &scope).await.unwrap();
    let reset = db
        .store
        .reset_analysis(
            DEVICE,
            &ResetCommand {
                operation_id: "insight-reset".into(),
                scope,
                token: preview.token,
            },
            HistoryWorker::versions(),
        )
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(brief(&db).await["metrics"][0]["value"], 3600.0);
    db.store
        .undo_reset(
            DEVICE,
            &UndoReset {
                operation_id: "insight-undo".into(),
                reset_id: reset.operation_id,
            },
            HistoryWorker::versions(),
        )
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(brief(&db).await["metrics"][0]["value"], 3000.0);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
    // Removing the main sleep removes it from both brief and subsequent baselines.
    let row = access.get_session(DEVICE, row.id).await.unwrap().unwrap();
    access
        .correct_workout(
            DEVICE,
            &WorkoutCorrection {
                operation_id: "insight-remove".into(),
                action: "remove".into(),
                targets: vec![SessionRevision {
                    id: row.id,
                    revision: row.revision,
                }],
                intervals: vec![],
                undo_id: None,
            },
            HistoryWorker::versions().sleep,
        )
        .await
        .unwrap();
    drain(&db).await;
    assert_eq!(brief(&db).await["state"], "no_sleep");
    let later = morning_insights(&db.store, DEVICE, day("2025-01-16"), "UTC")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(later.metrics[0].baseline.count, 14);
}
