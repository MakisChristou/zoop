//! Health sync must preserve identities, sample gaps, source ownership and cursor fences.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::{Value, json};
use support::{DEVICE, Db};
use tower::ServiceExt;
use zoop_api::{AppState, build_router};
async fn request(db: &Db, method: &str, path: &str, body: Value, auth: bool) -> (u16, Value) {
    let mut r = Request::builder()
        .method(method)
        .uri(format!("/v1/devices/{DEVICE}/{path}"))
        .header("content-type", "application/json");
    if auth {
        r = r.header("authorization", "Bearer test-token");
    }
    let response = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(r.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}
async fn seed(db: &Db) {
    let raw = db.raw(1).await;
    sqlx::query("INSERT INTO samples(device_id,ts,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-01-01T00:00:00Z'::timestamptz+n*interval '1 second',n,1,CASE WHEN n<10 OR n>=20 THEN 2 ELSE 0 END,$2 FROM generate_series(0,39)n WHERE n<>30")
 .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,fixed) VALUES('TEST-RELIABILITY','2025-01-01T00:00:00Z','2025-01-01T00:00:40Z','main','main',true)").await;
    db.sql("INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind) VALUES('TEST-RELIABILITY','2025-01-01T02:00:00Z','2025-01-01T03:00:00Z','resistance','resistance')").await;
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sleep_gaps_metric_updates_removal_undo_and_snapshot_watermark() {
    let db = Db::new().await;
    seed(&db).await;
    let first = db
        .store
        .health_page(DEVICE, 0, None, true, 1)
        .await
        .unwrap();
    assert!(!first.done);
    let sleep = &first.records[0];
    assert_eq!(sleep.domain, "sleep");
    assert_eq!(sleep.payload["intervals"].as_array().unwrap().len(), 3);
    let sum: i64 = sleep.payload["intervals"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (support::at(r["end"].as_str().unwrap()) - support::at(r["start"].as_str().unwrap()))
                .num_seconds()
        })
        .sum();
    assert_eq!(sum, 29);
    db.sql("UPDATE sleep_sessions SET metrics=jsonb_build_object('unrelated',1)")
        .await;
    assert_eq!(
        db.store.health_info(DEVICE).await.unwrap().cursor,
        first.watermark,
        "no-op export does not churn version"
    );
    db.sql("UPDATE sleep_sessions SET end_ts=end_ts-interval '5 seconds',metrics_pending=true")
        .await;
    assert_eq!(
        db.store.health_info(DEVICE).await.unwrap().cursor,
        first.watermark,
        "pending metrics retain last export"
    );
    db.sql("UPDATE sleep_sessions SET metrics_pending=false")
        .await;
    let second = db
        .store
        .health_page(DEVICE, first.next_cursor, Some(first.watermark), true, 10)
        .await
        .unwrap();
    assert!(second.done);
    assert_eq!(second.records.len(), 1);
    assert_eq!(second.records[0].domain, "workout");
    let changes = db
        .store
        .health_page(DEVICE, first.watermark, None, false, 10)
        .await
        .unwrap();
    assert_eq!(changes.records.len(), 1);
    assert_eq!(changes.records[0].version, 2);
    db.sql("UPDATE sleep_sessions SET status='removed'").await;
    let removed = db
        .store
        .health_page(DEVICE, changes.watermark, None, false, 10)
        .await
        .unwrap();
    assert!(removed.records[0].removed);
    db.sql("UPDATE sleep_sessions SET status='active'").await;
    let restored = db
        .store
        .health_page(DEVICE, removed.watermark, None, false, 10)
        .await
        .unwrap();
    assert!(!restored.records[0].removed);
    assert_eq!(restored.records[0].version, 4);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn weight_retries_conflicts_imports_and_source_deletion() {
    let db = Db::new().await;
    let mut w = json!({"id":"snoop:test-weight","measured_at":"2025-01-01T08:00:00Z","kg":80.2,"source":"snoop","source_name":"Zoop","version":0,"removed":false});
    assert_eq!(
        request(&db, "PUT", "weights", w.clone(), false).await.0,
        401
    );
    let (status, saved) = request(&db, "PUT", "weights", w.clone(), true).await;
    assert_eq!(status, 200);
    assert_eq!(saved["version"], 1);
    assert_eq!(
        request(&db, "PUT", "weights", w.clone(), true).await.1["version"],
        1
    );
    w["kg"] = json!(81.0);
    assert_eq!(request(&db, "PUT", "weights", w.clone(), true).await.0, 409);
    w["version"] = json!(1);
    assert_eq!(
        request(&db, "PUT", "weights", w.clone(), true).await.1["version"],
        2
    );
    w["id"] = json!("health:test-weight");
    w["source"] = json!("health");
    w["source_name"] = json!("Test scale");
    w["version"] = json!(0);
    assert_eq!(request(&db, "PUT", "weights", w.clone(), true).await.0, 200);
    assert_eq!(
        db.count("SELECT count(*) FROM health_exports WHERE domain='weight'")
            .await,
        1,
        "imports never exported"
    );
    assert_eq!(
        request(
            &db,
            "POST",
            "weights/remove-imports",
            json!({"ids":["snoop:test-weight","health:test-weight"]}),
            true
        )
        .await
        .0,
        200
    );
    assert_eq!(
        db.count("SELECT count(*) FROM weight_readings WHERE removed AND source='snoop'")
            .await,
        0
    );
    assert_eq!(
        db.count("SELECT count(*) FROM weight_readings WHERE removed AND source='health'")
            .await,
        1
    );
    w["kg"] = json!(-2);
    assert_eq!(request(&db, "PUT", "weights", w, true).await.0, 400);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn steps_are_timed_idempotent_and_correctable() {
    let db = Db::new().await;
    seed(&db).await;
    let d = support::day("2025-01-01");
    db.store.prepare_health_steps(DEVICE, d, d).await.unwrap();
    let first = db
        .store
        .health_page(DEVICE, 0, None, true, 100)
        .await
        .unwrap();
    let steps = first.records.iter().find(|r| r.domain == "steps").unwrap();
    assert_eq!(steps.payload["count"], 39);
    assert_eq!((steps.end_ts - steps.start_ts).num_seconds(), 60);
    db.store.prepare_health_steps(DEVICE, d, d).await.unwrap();
    assert_eq!(
        db.store.health_info(DEVICE).await.unwrap().cursor,
        first.watermark
    );
    db.sql("UPDATE samples SET activity=0").await;
    db.sql("SELECT project_health_steps('TEST-RELIABILITY','2025-01-01','2025-01-02')")
        .await;
    let changed = db
        .store
        .health_page(DEVICE, first.watermark, None, false, 100)
        .await
        .unwrap();
    assert_eq!(changed.records.len(), 1);
    assert!(changed.records[0].removed);
    assert_eq!(
        request(&db, "GET", "health/exports?cursor=-1", Value::Null, true)
            .await
            .0,
        409
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn simultaneous_publications_cannot_commit_below_a_consumed_cursor() {
    let db = Db::new().await;
    let mut first = db.pool.begin().await.unwrap();
    sqlx::query(
        "SELECT publish_health($1,'test:one','workout','2025-01-01','2025-01-02','{}',false)",
    )
    .bind(DEVICE)
    .execute(&mut *first)
    .await
    .unwrap();
    let pool = db.pool.clone();
    let second = tokio::spawn(async move {
        sqlx::query(
            "SELECT publish_health($1,'test:two','workout','2025-01-01','2025-01-02','{}',false)",
        )
        .bind(DEVICE)
        .execute(&pool)
        .await
        .unwrap();
    });
    first.commit().await.unwrap();
    second.await.unwrap();
    let page = db
        .store
        .health_page(DEVICE, 0, None, false, 1)
        .await
        .unwrap();
    assert!(!page.done);
    let rest = db
        .store
        .health_page(DEVICE, page.next_cursor, Some(page.watermark), false, 1)
        .await
        .unwrap();
    assert!(rest.done);
    assert_ne!(page.records[0].id, rest.records[0].id);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn wake_reminder_needs_sustained_recent_awake_samples_and_automatic_main() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind) VALUES('TEST-RELIABILITY',now()-interval '8 hours',now()-interval '40 minutes','main','main')").await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    sqlx::query("INSERT INTO samples(device_id,ts,band_state,raw_frame_id) SELECT $1,now()-interval '40 minutes'+n*interval '1 second',0,$2 FROM generate_series(0,2399)n")
 .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_some()
    );
    db.sql("UPDATE sleep_sessions SET edited=true").await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    db.sql("UPDATE sleep_sessions SET edited=false,kind='nap'")
        .await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    db.sql("UPDATE sleep_sessions SET kind='main',metrics_pending=true")
        .await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    db.sql("UPDATE sleep_sessions SET metrics_pending=false; UPDATE samples SET band_state=2 WHERE ts>now()-interval '5 minutes'").await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn weight_delta_pages_updates_tombstones_and_auth() {
    let db = Db::new().await;
    assert_eq!(
        request(&db, "GET", "weight-changes", json!(null), false)
            .await
            .0,
        401
    );
    let mut inputs = Vec::new();
    for n in 0..3 {
        let input = json!({"id":format!("health:reading-{n}"),"measured_at":"2025-01-01T08:00:00Z","kg":80.0+n as f64,"source":"health","source_name":"Test","version":0,"removed":false});
        let (status, saved) = request(&db, "PUT", "weights", input, true).await;
        assert_eq!(status, 200);
        inputs.push(saved);
    }
    let (status, first) = request(
        &db,
        "GET",
        "weight-changes?cursor=0&limit=1",
        json!(null),
        true,
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(first["rows"].as_array().unwrap().len(), 1);
    assert_eq!(first["done"], false);
    let watermark = first["watermark"].as_i64().unwrap();
    // A not-yet-read row changes beyond this pass's watermark. Next pass must recover it.
    inputs[2]["kg"] = json!(90.0);
    assert_eq!(
        request(&db, "PUT", "weights", inputs[2].clone(), true)
            .await
            .0,
        200
    );
    let path = format!(
        "weight-changes?cursor={}&watermark={watermark}",
        first["next_cursor"]
    );
    let (_, rest) = request(&db, "GET", &path, json!(null), true).await;
    assert_eq!(rest["done"], true);
    assert_eq!(rest["next_cursor"], watermark);
    let (_, next) = request(
        &db,
        "GET",
        &format!("weight-changes?cursor={watermark}"),
        json!(null),
        true,
    )
    .await;
    assert_eq!(next["rows"].as_array().unwrap().len(), 1);
    assert_eq!(next["rows"][0]["kg"], 90.0);
    let cursor = next["next_cursor"].as_i64().unwrap();
    inputs[0]["removed"] = json!(true);
    assert_eq!(
        request(&db, "PUT", "weights", inputs[0].clone(), true)
            .await
            .0,
        200
    );
    let (_, deleted) = request(
        &db,
        "GET",
        &format!("weight-changes?cursor={cursor}"),
        json!(null),
        true,
    )
    .await;
    assert_eq!(deleted["rows"][0]["removed"], true);
    assert_eq!(
        request(&db, "GET", "weight-changes?cursor=-1", json!(null), true)
            .await
            .0,
        400
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn wake_reminder_accepts_batched_uploads_but_rejects_stale_or_sleeping_windows() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind) VALUES('TEST-RELIABILITY',now()-interval '8 hours',now()-interval '50 minutes','main','main')").await;
    // Samples arrived together, six minutes behind wall-clock time. The newest
    // five minutes still contain a full awake window; no instant upload is required.
    sqlx::query("INSERT INTO samples(device_id,ts,band_state,raw_frame_id) SELECT $1,now()-interval '50 minutes'+n*interval '1 second',0,$2 FROM generate_series(0,2640)n")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_some()
    );
    db.sql("UPDATE samples SET band_state=2 WHERE ts>now()-interval '7 minutes'")
        .await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    db.sql(
        "UPDATE samples SET band_state=0; DELETE FROM samples WHERE ts>now()-interval '16 minutes'",
    )
    .await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn wake_reminder_rejects_sparse_batches_and_unfinished_sleep_analysis() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind) VALUES('TEST-RELIABILITY',now()-interval '8 hours',now()-interval '50 minutes','main','main')").await;
    sqlx::query("INSERT INTO samples(device_id,ts,band_state,raw_frame_id) SELECT $1,now()-interval '50 minutes'+n*interval '1 second',0,$2 FROM generate_series(0,1800)n UNION ALL SELECT $1,now()-interval '6 minutes',0,$2")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
    sqlx::query("INSERT INTO samples(device_id,ts,band_state,raw_frame_id) SELECT $1,now()-interval '11 minutes'+n*interval '1 second',0,$2 FROM generate_series(0,298)n")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_some()
    );
    db.sql("UPDATE sleep_sessions SET metrics_pending=true")
        .await;
    assert!(
        db.store
            .health_info(DEVICE)
            .await
            .unwrap()
            .wake_at
            .is_none()
    );
}
