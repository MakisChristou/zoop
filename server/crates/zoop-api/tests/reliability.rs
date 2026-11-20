#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::Request,
};
use base64::Engine;
use serde_json::{Value, json};
use support::*;
use tower::ServiceExt;
use zoop_api::{AppState, build_router};

fn router(db: &Db) -> Router {
    build_router(AppState::new(db.store.clone(), "test-token".into()))
}
async fn post(app: Router, path: &str, frames: Value) -> (u16, Value) {
    let request = Request::post(path)
        .header("authorization", "Bearer test-token")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"device_id":DEVICE,"model":"TEST","frames":frames}).to_string(),
        ))
        .unwrap();
    let response = app.oneshot(request).await.unwrap();
    let status = response.status().as_u16();
    let body = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap())
}
fn frame(seq: i64, id: Option<&str>, inner: &[u8]) -> Value {
    json!({"client_seq":seq,"upload_id":id,"channel":5,"received_at":"2025-01-01T00:00:00Z",
        "bytes":base64::engine::general_purpose::STANDARD.encode(zoop_proto::encode_frame(inner,1,0))})
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn mixed_receipts_lost_response_legacy_conflict_and_unknown_payloads() {
    let db = Db::new().await;
    let good = frame(
        1,
        Some("00000000-0000-4000-8000-000000000001"),
        &[0xfe, 0, 0, 0],
    );
    let mut invalid = good.clone();
    invalid["client_seq"] = json!(2);
    invalid["bytes"] = json!("bad base64");
    let (status, body) = post(router(&db), "/v2/ingest", json!([good, invalid])).await;
    assert_eq!(status, 200);
    assert_eq!(body["results"][0]["status"], "stored");
    assert_eq!(body["results"][1]["status"], "rejected");
    // Retrying after the response was lost verifies bytes and returns a receipt.
    let (_, retry) = post(router(&db), "/v2/ingest", json!([good])).await;
    assert_eq!(retry["results"][0]["status"], "duplicate");
    let different = frame(
        1,
        Some("00000000-0000-4000-8000-000000000001"),
        &[0xfd, 0, 0, 0],
    );
    let (_, conflict) = post(router(&db), "/v2/ingest", json!([different])).await;
    assert_eq!(conflict["results"][0]["status"], "conflict");
    // Old clients must not get a 2xx for any partial batch.
    let legacy = frame(1, None, &[0xfe, 0, 0, 0]);
    assert_eq!(
        post(router(&db), "/v1/ingest", json!([legacy, invalid]))
            .await
            .0,
        400
    );
    let (code, body) = post(router(&db), "/v1/ingest", json!([legacy])).await;
    assert_eq!(code, 200);
    assert_eq!(body["duplicates"], 1);
    // A well-formed envelope with malformed known payload is durable for decoder repair.
    let semantic = frame(
        3,
        Some("00000000-0000-4000-8000-000000000003"),
        &[47, 0, 0, 0],
    );
    assert_eq!(
        post(router(&db), "/v2/ingest", json!([semantic])).await.1["accepted"],
        1
    );
    let decoder = zoop_core::Decoder::new(db.store.clone(), 500, std::time::Duration::from_secs(1));
    decoder.pass().await.unwrap();
    let status = db
        .store
        .processing_status(DEVICE, zoop_proto::PROTO_VERSION, VERSIONS)
        .await
        .unwrap();
    assert_eq!(status.pending_decode, 0);
    assert_eq!(status.decode_failures, 1);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 3);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn status_distinguishes_readiness_stale_workers_and_paused_history() {
    let db = Db::new().await;
    let request = || Request::get("/ready").body(Body::empty()).unwrap();
    assert_eq!(router(&db).oneshot(request()).await.unwrap().status(), 503);
    db.store
        .worker_heartbeat("decoder", None, false)
        .await
        .unwrap();
    db.store
        .worker_heartbeat("analysis", None, false)
        .await
        .unwrap();
    assert_eq!(router(&db).oneshot(request()).await.unwrap().status(), 200);
    db.store
        .worker_heartbeat("analysis", None, true)
        .await
        .unwrap();
    assert_eq!(router(&db).oneshot(request()).await.unwrap().status(), 503);
    db.store
        .worker_heartbeat("analysis", None, false)
        .await
        .unwrap();
    db.sql("UPDATE worker_status SET heartbeat_at=now()-interval '3 minutes' WHERE name='decoder'")
        .await;
    assert_eq!(router(&db).oneshot(request()).await.unwrap().status(), 503);
    let path = format!("/v1/devices/{DEVICE}/processing");
    assert_eq!(
        router(&db)
            .oneshot(Request::get(&path).body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status(),
        401
    );
    let response = router(&db)
        .oneshot(
            Request::get(path)
                .header("authorization", "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn worker_automatically_backfills_old_days_and_preserves_corrections() {
    let db = Db::new().await;
    let versions = zoop_core::HistoryWorker::versions();
    let first = db.raw(1).await;
    // A continuous thirty-five-minute walk, long before the former two-day window.
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id)
        SELECT $1,'2025-01-01 10:00:00Z'::timestamptz+make_interval(secs=>n),110,ARRAY[545],n*2,1,1,$2 FROM generate_series(0,2100) n")
        .bind(DEVICE).bind(first).execute(&db.pool).await.unwrap();
    db.store.seed_history(versions).await.unwrap();
    let worker =
        zoop_core::HistoryWorker::new(db.store.clone(), true, std::time::Duration::from_secs(60));
    for _ in 0..10 {
        if !worker.pass().await.unwrap() {
            break;
        }
    }
    let sessions = db
        .store
        .list_workouts(DEVICE, versions.workout, 10)
        .await
        .unwrap();
    assert_eq!(sessions.len(), 1);
    assert!(!sessions[0].notification_eligible);
    let original = sessions[0].id;
    db.store
        .upsert_label(
            DEVICE,
            sessions[0].start_ts,
            sessions[0].end_ts,
            "resistance",
        )
        .await
        .unwrap();
    let days = db
        .store
        .list_days(DEVICE, "UTC", 30, versions.workout)
        .await
        .unwrap();
    assert_eq!(days.len(), 1);
    assert!(days[0].load.is_some());
    // Late input invalidates the old day, survives a worker restart and retains its session identity and label.
    let second = db.raw(2).await;
    db.store
        .save_decoded(
            &[zoop_storage::DecodedFrame {
                frame_id: second,
                device_id: DEVICE,
                output: zoop_storage::DecodeOutput::Sample(sample(
                    second,
                    at("2025-01-01T10:10:00Z"),
                )),
            }],
            zoop_proto::PROTO_VERSION,
            versions,
        )
        .await
        .unwrap();
    db.sql("UPDATE analysis_jobs SET available_at=now()").await;
    let replacement =
        zoop_core::HistoryWorker::new(db.store.clone(), true, std::time::Duration::from_secs(60));
    for _ in 0..20 {
        if !replacement.pass().await.unwrap() {
            break;
        }
    }
    let sessions = db
        .store
        .list_workouts(DEVICE, versions.workout, 10)
        .await
        .unwrap();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].id, original);
    assert_eq!(sessions[0].kind, "resistance");
    assert_eq!(
        db.store
            .processing_status(DEVICE, 3, versions)
            .await
            .unwrap()
            .pending_analysis,
        0
    );
}
