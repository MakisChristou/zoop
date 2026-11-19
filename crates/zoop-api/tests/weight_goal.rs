//! Real Postgres contracts: revision safety, source priority and read-only summaries.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::{Value, json};
use support::{DEVICE, Db, at, day};
use tower::ServiceExt;
use zoop_api::{AppState, build_router};
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
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','health:aaaa','2025-03-29T23:30:00Z',62.4,'health','Test',false),('TEST-RELIABILITY','zoop:aaaaa','2025-03-30T10:00:00Z',70,'snoop','Zoop',false),('TEST-RELIABILITY','health:bbbb','2025-03-30T11:00:00Z',62.5,'health','Test',false),('TEST-RELIABILITY','health:cccc','2025-03-30T12:00:00Z',65,'health','Test',true),('TEST-RELIABILITY','health:dddd','2025-03-31T07:00:00Z',65,'health','Test',false)").await;
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

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn finish_date_validation_legacy_client_and_clear_preserve_phase() {
    let db = Db::new().await;
    let today = chrono::Utc::now().date_naive();
    let mut q = input();
    q["timezone"] = json!("UTC");
    for date in [
        today - chrono::Duration::days(1),
        today,
        today + chrono::Duration::days(731),
    ] {
        q["finish_date"] = json!(date);
        assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.0, 400);
    }
    let finish = today + chrono::Duration::days(56);
    q["finish_date"] = json!(finish);
    let (status, first) = call(&db, DEVICE, Some(q.clone()), true).await;
    assert_eq!(status, 200);
    assert_eq!(first["finish_date"], json!(finish));
    assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.1, first);
    q.as_object_mut().unwrap().remove("finish_date");
    q["revision"] = json!(1);
    q["reminder_minute"] = json!(1100);
    let saved = call(&db, DEVICE, Some(q.clone()), true).await.1;
    assert_eq!(saved["finish_date"], json!(finish));
    assert_eq!(saved["started_at"], first["started_at"]);
    q["revision"] = json!(2);
    q["finish_date"] = Value::Null;
    let cleared = call(&db, DEVICE, Some(q.clone()), true).await.1;
    assert!(cleared["finish_date"].is_null());
    assert_eq!(cleared["pace_started_at"], first["pace_started_at"]);
    q["revision"] = json!(3);
    q["finish_date"] = json!(finish + chrono::Duration::days(7));
    let edited = call(&db, DEVICE, Some(q), true).await.1;
    assert_eq!(edited["pace_started_at"], first["pace_started_at"]);
    let response = call(&db, DEVICE, None, true).await.1;
    assert_eq!(response["summary"]["progress"]["weeks_remaining"], 9);
    assert!(response["summary"]["progress"]["target_weight_kg"].is_null());
    assert_eq!(db.count("SELECT count(*) FROM weight_readings").await, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn old_finished_cut_uses_original_health_baseline_and_excludes_later_weights() {
    let db = Db::new().await;
    call(&db, DEVICE, Some(input()), true).await;
    db.sql("UPDATE weight_goals SET started_at='2020-11-16T10:00:00Z',pace_started_at='2020-11-16T10:00:00Z',timezone='UTC',finish_date='2020-11-30'").await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','health:start','2020-11-16T08:00:00Z',63,'health','Test',false),('TEST-RELIABILITY','zoop:start','2020-11-16T09:00:00Z',80,'snoop','Test',false),('TEST-RELIABILITY','health:end','2020-11-30T08:00:00Z',61,'health','Test',false),('TEST-RELIABILITY','health:later','2020-12-01T08:00:00Z',80,'health','Test',false)").await;
    let before = db
        .count("SELECT sum(version)::bigint FROM weight_readings")
        .await;
    let (status, r) = call(&db, DEVICE, None, true).await;
    assert_eq!(status, 200);
    let p = &r["summary"]["progress"];
    assert_eq!(p["starting_weight_kg"], 63.0);
    assert_eq!(p["current_weight_kg"], 61.0);
    assert_eq!(p["total_lost_kg"], 2.0);
    assert_eq!(p["target_weight_kg"], 62.4);
    assert_eq!(p["completed"], true);
    assert_eq!(p["weeks_remaining"], 0);
    assert_eq!(
        before,
        db.count("SELECT sum(version)::bigint FROM weight_readings")
            .await
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn cut_steps_are_optional_revisioned_and_do_not_reset_weight_pace() {
    let db = Db::new().await;
    let mut q = input();
    for steps in [-1, 0, 100001] {
        q["daily_steps_goal"] = json!(steps);
        assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.0, 400);
    }
    q["daily_steps_goal"] = json!(8000);
    let (status, first) = call(&db, DEVICE, Some(q.clone()), true).await;
    assert_eq!(status, 200);
    assert_eq!(first["daily_steps_goal"], 8000);
    assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.1, first);
    q["revision"] = json!(1);
    q["daily_steps_goal"] = json!(9000);
    let saved = call(&db, DEVICE, Some(q.clone()), true).await.1;
    assert_eq!(saved["daily_steps_goal"], 9000);
    assert_eq!(saved["pace_started_at"], first["pace_started_at"]);
    assert_eq!(saved["started_at"], first["started_at"]);
    q["revision"] = json!(2);
    q.as_object_mut().unwrap().remove("daily_steps_goal");
    q["reminder_minute"] = json!(1100);
    assert_eq!(
        call(&db, DEVICE, Some(q.clone()), true).await.1["daily_steps_goal"],
        9000
    );
    q["revision"] = json!(3);
    q["daily_steps_goal"] = Value::Null;
    assert!(call(&db, DEVICE, Some(q), true).await.1["daily_steps_goal"].is_null());
    assert_eq!(db.count("SELECT count(*) FROM weight_readings").await, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn first_latest_progress_keeps_weekly_median_and_measurements_unchanged() {
    let db = Db::new().await;
    call(&db, DEVICE, Some(input()), true).await;
    db.sql("UPDATE weight_goals SET started_at='2020-11-16T12:00:00Z',pace_started_at='2020-11-16T12:00:00Z',timezone='UTC',finish_date='2020-11-17',weekly_loss_kg=0.8").await;
    db.sql(
        "INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES
      ('TEST-RELIABILITY','pre-cut','2020-11-15T08:00:00Z',69.9,'snoop','Test',false),
      ('TEST-RELIABILITY','start','2020-11-16T08:00:00Z',70.6,'snoop','Test',false),
      ('TEST-RELIABILITY','latest','2020-11-17T08:00:00Z',69.9,'snoop','Test',false),
      ('TEST-RELIABILITY','deleted','2020-11-17T09:00:00Z',90,'health','Test',true),
      ('TEST-RELIABILITY','after-finish','2020-11-18T08:00:00Z',80,'health','Test',false)",
    )
    .await;
    let before = db
        .count("SELECT sum(version)::bigint FROM weight_readings")
        .await;
    let (status, r) = call(&db, DEVICE, None, true).await;
    assert_eq!(status, 200);
    let p = &r["summary"]["progress"];
    assert_eq!(
        p["weigh_ins"],
        json!([{"day":"2020-11-16","kg":70.6},{"day":"2020-11-17","kg":69.9}])
    );
    assert_eq!(p["starting_weight_kg"], 70.6);
    assert_eq!(p["current_weight_kg"], 69.9);
    assert!((p["total_lost_kg"].as_f64().unwrap() - 0.7).abs() < 1e-9);
    assert!((p["target_weight_kg"].as_f64().unwrap() - (70.6 - 0.8 / 7.0)).abs() < 1e-9);
    assert_eq!(r["summary"]["median_kg"], 70.25);
    assert_eq!(r["summary"]["count"], 2);
    assert_eq!(
        before,
        db.count("SELECT sum(version)::bigint FROM weight_readings")
            .await
    );
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_revisions").await,
        1
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sparse_long_cut_endpoints_outlive_weekly_history_window() {
    let db = Db::new().await;
    call(&db, DEVICE, Some(input()), true).await;
    db.sql("UPDATE weight_goals SET started_at='2020-01-01T12:00:00Z',pace_started_at='2020-01-01T12:00:00Z',timezone='UTC',finish_date='2020-12-31',weekly_loss_kg=0.1").await;
    db.sql(
        "INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES
      ('TEST-RELIABILITY','pre-cut','2019-12-31T08:00:00Z',90,'health','Test'),
      ('TEST-RELIABILITY','start','2020-01-20T08:00:00Z',80,'snoop','Test'),
      ('TEST-RELIABILITY','middle','2020-03-01T08:00:00Z',79,'snoop','Test'),
      ('TEST-RELIABILITY','last','2020-06-01T08:00:00Z',78,'snoop','Test'),
      ('TEST-RELIABILITY','after','2021-01-01T08:00:00Z',70,'snoop','Test')",
    )
    .await;
    let (status, r) = call(&db, DEVICE, None, true).await;
    assert_eq!(status, 200);
    let p = &r["summary"]["progress"];
    assert_eq!(
        p["weigh_ins"],
        json!([{"day":"2020-01-20","kg":80.0},{"day":"2020-03-01","kg":79.0},{"day":"2020-06-01","kg":78.0}])
    );
    assert_eq!(p["starting_weight_kg"], 80.0);
    assert_eq!(p["current_weight_kg"], 78.0);
    assert_eq!(p["total_lost_kg"], 2.0);
    assert!((p["target_weight_kg"].as_f64().unwrap() - (80.0 - 0.1 * 365.0 / 7.0)).abs() < 1e-9);
    assert!(r["summary"]["median_kg"].is_null());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn endpoints_preserve_local_day_health_priority_and_future_filter() {
    let db = Db::new().await;
    db.sql(
        "INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES
      ('TEST-RELIABILITY','pre-cut','2025-03-29T22:59:00Z',90,'health','Test',false),
      ('TEST-RELIABILITY','first','2025-03-29T23:30:00Z',70,'health','Test',false),
      ('TEST-RELIABILITY','same-day-zoop','2025-03-30T10:00:00Z',80,'snoop','Test',false),
      ('TEST-RELIABILITY','last','2025-03-30T22:30:00Z',69,'health','Test',false),
      ('TEST-RELIABILITY','deleted','2025-03-30T22:45:00Z',90,'health','Test',true),
      ('TEST-RELIABILITY','future','2025-03-31T08:00:00Z',60,'health','Test',false)",
    )
    .await;
    let rows = db
        .store
        .cut_weight_days(
            DEVICE,
            "Europe/Berlin",
            day("2025-03-30"),
            day("2025-03-31"),
            at("2025-03-30T23:00:00Z"),
        )
        .await
        .unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].day, day("2025-03-30"));
    assert_eq!(rows[0].kg, 70.0);
    assert_eq!(rows[1].day, day("2025-03-31"));
    assert_eq!(rows[1].kg, 69.0);
    let single = db
        .store
        .cut_weight_days(
            DEVICE,
            "Europe/Berlin",
            day("2025-03-30"),
            day("2025-03-30"),
            at("2025-03-30T23:00:00Z"),
        )
        .await
        .unwrap();
    assert_eq!(single.len(), 1);
    assert_eq!(single[0].kg, 70.0);
    assert!(
        db.store
            .cut_weight_days(
                DEVICE,
                "Europe/Berlin",
                day("2025-04-01"),
                day("2025-03-31"),
                at("2025-04-02T12:00:00Z")
            )
            .await
            .unwrap()
            .is_empty()
    );
}
