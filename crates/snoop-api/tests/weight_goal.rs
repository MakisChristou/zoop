//! Real Postgres contracts: revision safety, source priority and read-only summaries.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::{Value, json};
use snoop_api::{AppState, build_router};
use support::{DEVICE, Db, at, day};
use tower::ServiceExt;
async fn call(db: &Db, device: &str, body: Option<Value>, auth: bool) -> (u16, Value) {
    let mut r = Request::builder()
        .method(if body.is_some() { "PUT" } else { "GET" })
        .uri(format!("/v1/devices/{device}/weight-goal"))
        .header("content-type", "application/json");
    if auth {
        r = r.header("authorization", "Bearer test-token");
    }
    let response = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(
            r.body(body.map_or(Body::empty(), |v| Body::from(v.to_string())))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = to_bytes(response.into_body(), 100000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
fn input() -> Value {
    json!({"revision":0,"active":true,"timezone":"Europe/Berlin","weekly_loss_kg":0.3,"reminder_enabled":true,"reminder_weekday":1,"reminder_minute":1200})
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn opt_in_validation_revision_conflict_retry_and_pause() {
    let db = Db::new().await;
    assert_eq!(call(&db, DEVICE, None, false).await.0, 401);
    assert_eq!(call(&db, "UNKNOWN", None, true).await.0, 404);
    assert!(call(&db, DEVICE, None, true).await.1["goal"].is_null());
    for (key, value) in [
        ("timezone", json!("Not/AZone")),
        ("weekly_loss_kg", json!(-0.5)),
        ("reminder_weekday", json!(8)),
        ("reminder_minute", json!(1440)),
    ] {
        let mut q = input();
        q[key] = value;
        assert_eq!(call(&db, DEVICE, Some(q), true).await.0, 400);
    }
    let (status, first) = call(&db, DEVICE, Some(input()), true).await;
    assert_eq!(status, 200);
    assert_eq!(first["revision"], 1);
    assert_eq!(call(&db, DEVICE, Some(input()), true).await.1, first);
    let mut stale = input();
    stale["weekly_loss_kg"] = json!(0.4);
    assert_eq!(call(&db, DEVICE, Some(stale), true).await.0, 409);
    let mut next = input();
    next["revision"] = json!(1);
    next["reminder_minute"] = json!(1100);
    let saved = call(&db, DEVICE, Some(next.clone()), true).await.1;
    assert_eq!(saved["pace_started_at"], first["pace_started_at"]);
    next["revision"] = json!(2);
    next["weekly_loss_kg"] = json!(0.4);
    let changed = call(&db, DEVICE, Some(next.clone()), true).await.1;
    assert_ne!(changed["pace_started_at"], first["pace_started_at"]);
    assert_eq!(changed["started_at"], first["started_at"]);
    next["revision"] = json!(3);
    next["active"] = json!(false);
    assert_eq!(call(&db, DEVICE, Some(next), true).await.0, 200);
    let response = call(&db, DEVICE, None, true).await.1;
    assert!(response["summary"].is_null());
    assert_eq!(response["goal"]["active"], false);
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_revisions").await,
        4
    );
    assert_eq!(db.count("SELECT count(*) FROM weight_readings").await, 0);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn daily_health_priority_dst_deletions_and_bounded_read_only_summary() {
    let db = Db::new().await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','health:aaaa','2025-03-29T23:30:00Z',62.4,'health','Test',false),('TEST-RELIABILITY','snoop:aaaaa','2025-03-30T10:00:00Z',70,'snoop','Snoop',false),('TEST-RELIABILITY','health:bbbb','2025-03-30T11:00:00Z',62.5,'health','Test',false),('TEST-RELIABILITY','health:cccc','2025-03-30T12:00:00Z',65,'health','Test',true),('TEST-RELIABILITY','health:dddd','2025-03-31T07:00:00Z',65,'health','Test',false)").await;
    let rows = db
        .store
        .weight_goal_days(DEVICE, "Europe/Berlin", at("2025-03-30T20:00:00Z"))
        .await
        .unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].day, day("2025-03-30"));
    assert_eq!(rows[0].kg, 62.5);
    assert_eq!(
        db.store
            .weight_local_day(at("2025-03-30T22:00:00Z"), "Europe/Berlin")
            .await
            .unwrap(),
        day("2025-03-31")
    );
    call(&db, DEVICE, Some(input()), true).await;
    let before = db
        .count("SELECT coalesce(sum(version),0)::bigint FROM weight_readings")
        .await;
    let (status, r) = call(&db, DEVICE, None, true).await;
    assert_eq!(status, 200);
    assert_eq!(r["summary"]["state"], "starting");
    assert_eq!(
        before,
        db.count("SELECT coalesce(sum(version),0)::bigint FROM weight_readings")
            .await
    );
}
