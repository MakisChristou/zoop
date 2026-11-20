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
    assert_eq!(
        call(&db, DEVICE, None, true).await.1["goal"]["phase"],
        "maintenance"
    );
    let db = Db::new().await;
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
    assert!(response["summary"].is_object());
    assert_eq!(response["goal"]["phase"], "maintenance");
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
    assert_eq!(r["summary"]["state"], "building_trend");
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
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period; UPDATE weight_goals SET started_at='2020-11-16T10:00:00Z',pace_started_at='2020-11-16T10:00:00Z',timezone='UTC',finish_date='2020-11-30'; ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period").await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','health:start','2020-11-16T08:00:00Z',63,'health','Test',false),('TEST-RELIABILITY','zoop:start','2020-11-16T09:00:00Z',80,'snoop','Test',false),('TEST-RELIABILITY','health:end','2020-11-30T08:00:00Z',61,'health','Test',false),('TEST-RELIABILITY','health:later','2020-12-01T08:00:00Z',80,'health','Test',false)").await;
    let before = db
        .count("SELECT sum(version)::bigint FROM weight_readings")
        .await;
    let (status, r) = call(&db, DEVICE, None, true).await;
    assert_eq!(status, 200);
    assert_eq!(r["goal"]["phase"], "maintenance");
    let (_, history) = history_call(&db, "weight-goals").await;
    let (_, r) = history_call(&db, &format!("weight-goals/{}", history["items"][0]["id"])).await;
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
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period; UPDATE weight_goals SET started_at='2020-11-16T12:00:00Z',pace_started_at='2020-11-16T12:00:00Z',timezone='UTC',finish_date='2020-11-17',weekly_loss_kg=0.8; ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period").await;
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
    assert_eq!(r["goal"]["phase"], "maintenance");
    let (_, history) = history_call(&db, "weight-goals").await;
    let (_, r) = history_call(&db, &format!("weight-goals/{}", history["items"][0]["id"])).await;
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
        3
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sparse_long_cut_endpoints_outlive_weekly_history_window() {
    let db = Db::new().await;
    call(&db, DEVICE, Some(input()), true).await;
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period; UPDATE weight_goals SET started_at='2020-01-01T12:00:00Z',pace_started_at='2020-01-01T12:00:00Z',timezone='UTC',finish_date='2020-12-31',weekly_loss_kg=0.1; ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period").await;
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
    assert_eq!(r["goal"]["phase"], "maintenance");
    let (_, history) = history_call(&db, "weight-goals").await;
    let (_, r) = history_call(&db, &format!("weight-goals/{}", history["items"][0]["id"])).await;
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

async fn history_call(db: &Db, path: &str) -> (u16, Value) {
    let r = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(
            Request::builder()
                .uri(format!("/v1/devices/{DEVICE}/{path}"))
                .header("authorization", "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = r.status().as_u16();
    (
        status,
        serde_json::from_slice(&to_bytes(r.into_body(), 1_000_000).await.unwrap())
            .unwrap_or(Value::Null),
    )
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn end_restart_preserves_plan_and_bounds_history() {
    let db = Db::new().await;
    let mut q = input();
    q["timezone"] = json!("UTC");
    q["finish_date"] = json!(chrono::Utc::now().date_naive() + chrono::Duration::days(24));
    call(&db, DEVICE, Some(q.clone()), true).await;
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period; UPDATE weight_goals SET started_at=now()-interval '4 days',pace_started_at=now()-interval '4 days';
      INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES
      ('TEST-RELIABILITY','snoop:start',now()-interval '3 days',64.6,'snoop','Test',false),
      ('TEST-RELIABILITY','snoop:last',now()-interval '1 minute',63.9,'snoop','Test',false); ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period").await;
    let before = call(&db, DEVICE, None, true).await.1;
    let id = before["goal"]["id"].as_i64().unwrap();
    q["revision"] = before["goal"]["revision"].clone();
    q["active"] = json!(false);
    assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.0, 200);
    assert_eq!(call(&db, DEVICE, Some(q.clone()), true).await.0, 200);
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        1
    );
    let (_, closed) = history_call(&db, &format!("weight-goals/{id}")).await;
    assert_eq!(
        closed["summary"]["progress"]["target_weight_kg"],
        before["summary"]["progress"]["target_weight_kg"]
    );
    assert!(
        (closed["summary"]["progress"]["total_lost_kg"]
            .as_f64()
            .unwrap()
            - 0.7)
            .abs()
            < 1e-8
    );
    let receipt = call(&db, DEVICE, None, true).await.1;
    q["revision"] = receipt["goal"]["revision"].clone();
    q["phase"] = json!("cut");
    q["active"] = json!(true);
    let new = call(&db, DEVICE, Some(q.clone()), true).await.1;
    assert_ne!(new["id"], json!(id));
    assert_eq!(call(&db, DEVICE, Some(q), true).await.1["id"], new["id"]);
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','snoop:later',now()+interval '1 second',60,'snoop','Test',false)").await;
    let (_, after) = history_call(&db, &format!("weight-goals/{id}")).await;
    assert_eq!(after["summary"]["progress"], closed["summary"]["progress"]);
    let (_, list) = history_call(&db, "weight-goals?limit=1").await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    assert_eq!(list["items"][0]["goal"]["phase"], "maintenance");
    assert_eq!(db.count("SELECT count(*) FROM weight_readings").await, 3);
    assert_eq!(history_call(&db, "weight-goals/999999").await.0, 404);
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES ('TEST-RELIABILITY','health:late',now()-interval '3 days',65.0,'health','Test',false)").await;
    let (_, corrected) = history_call(&db, &format!("weight-goals/{id}")).await;
    assert_eq!(corrected["summary"]["progress"]["starting_weight_kg"], 65.0);
    assert_eq!(
        corrected["summary"]["progress"]["target_weight_kg"],
        closed["summary"]["progress"]["target_weight_kg"]
    );
    assert_eq!(
        call(&db, DEVICE, None, true).await.1["goal"]["id"],
        new["id"]
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn scheduled_expiry_is_once_at_local_midnight_and_same_day_end_has_no_fake_loss() {
    let db = Db::new().await;
    let mut q = input();
    q["timezone"] = json!("Europe/Berlin");
    call(&db, DEVICE, Some(q.clone()), true).await;
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period; UPDATE weight_goals SET started_at=now()-interval '10 days',pace_started_at=now()-interval '10 days',finish_date=(now() AT TIME ZONE timezone)::date-1; ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period").await;
    let response = call(&db, DEVICE, None, true).await.1;
    assert_eq!(response["goal"]["phase"], "maintenance");
    let (_, list) = history_call(&db, "weight-goals").await;
    assert_eq!(list["items"][0]["end_reason"], "scheduled");
    assert!(list["items"][0]["summary"]["progress"]["total_lost_kg"].is_null());
    call(&db, DEVICE, None, true).await;
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        1
    );
    assert_eq!(db.count("SELECT count(*) FROM weight_goal_history WHERE (ended_at AT TIME ZONE (settings->>'timezone'))::time='00:00'").await,1);
    q["revision"] = response["goal"]["revision"].clone();
    q["phase"] = json!("cut");
    q["finish_date"] =
        json!((chrono::Utc::now().date_naive() + chrono::Duration::days(28)).to_string());
    let restarted = call(&db, DEVICE, Some(q.clone()), true).await.1;
    q["revision"] = restarted["revision"].clone();
    q["active"] = json!(false);
    let (a, b) = tokio::join!(
        call(&db, DEVICE, Some(q.clone()), true),
        call(&db, DEVICE, Some(q), true)
    );
    assert_eq!(a.0, 200);
    assert_eq!(b.0, 200);
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        3
    );
    let (_, first) = history_call(&db, "weight-goals?limit=1").await;
    let cursor = first["next_cursor"].as_i64().unwrap();
    let (_, second) = history_call(&db, &format!("weight-goals?before={cursor}&limit=1")).await;
    assert_ne!(first["items"][0]["id"], second["items"][0]["id"]);
    assert!(second["next_cursor"].is_number());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn upgrade_recovers_periods_not_each_edit_and_preserves_current_goal() {
    let db = Db::new().await;
    // Recreate only the previous schema boundary inside this test's private schema.
    db.sql("DROP TRIGGER weight_goal_period ON weight_goals;
        DROP FUNCTION preserve_weight_goal_period();
        DROP FUNCTION closed_goal_target(text,jsonb,timestamptz);
        DROP TABLE weight_goal_history;
        ALTER TABLE weight_goals DROP COLUMN id;
        INSERT INTO weight_goals(device_id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date)
        VALUES('TEST-RELIABILITY',1,true,'2025-01-01T00:00:00Z','2025-01-01T00:00:00Z','UTC',0.3,false,1,1200,'2025-01-01T00:00:00Z','2025-02-01');
        INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w;
        UPDATE weight_goals SET revision=2,weekly_loss_kg=0.4,updated_at='2025-01-03T00:00:00Z';
        INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w;
        UPDATE weight_goals SET revision=3,active=false,updated_at='2025-01-15T00:00:00Z';
        INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w;
        UPDATE weight_goals SET revision=4,active=true,started_at=now(),pace_started_at=now(),updated_at=now(),finish_date=(now() AT TIME ZONE 'UTC')::date+28;
        INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w;").await;
    db.sql(include_str!("../../../migrations/0018_goal_history.sql"))
        .await;
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        1
    );
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_revisions").await,
        4
    );
    let response = call(&db, DEVICE, None, true).await.1;
    assert_eq!(response["goal"]["active"], true);
    assert_eq!(response["goal"]["revision"], 4);
    let (_, history) = history_call(&db, "weight-goals").await;
    assert_ne!(history["items"][0]["id"], response["goal"]["id"]);
    assert_eq!(history["items"][0]["goal"]["weekly_loss_kg"], 0.4);
    assert_eq!(history["items"][0]["end_reason"], "legacy");
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn simultaneous_edit_and_end_never_overwrite_the_winner() {
    let db = Db::new().await;
    let current = call(&db, DEVICE, Some(input()), true).await.1;
    let mut edit = input();
    edit["revision"] = current["revision"].clone();
    edit["weekly_loss_kg"] = json!(0.7);
    let mut end = input();
    end["revision"] = current["revision"].clone();
    end["active"] = json!(false);
    let (a, b) = tokio::join!(
        call(&db, DEVICE, Some(edit), true),
        call(&db, DEVICE, Some(end), true)
    );
    let mut statuses = [a.0, b.0];
    statuses.sort();
    assert_eq!(statuses, [200, 409]);
    let winner = if a.0 == 200 { a.1 } else { b.1 };
    let saved = call(&db, DEVICE, None, true).await.1;
    assert_eq!(saved["goal"], winner);
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        if winner["phase"] == "maintenance" {
            1
        } else {
            0
        }
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn phases_have_independent_steps_and_preserve_bulk_target_history() {
    let db = Db::new().await;
    let (a, b) = tokio::join!(call(&db, DEVICE, None, true), call(&db, DEVICE, None, true));
    assert_eq!(a.1["goal"]["id"], b.1["goal"]["id"]);
    let mut q = a.1["goal"].clone();
    assert_eq!(q["phase"], "maintenance");
    q["daily_steps_goal"] = json!(7000);
    q["reminder_enabled"] = json!(true);
    let saved = call(&db, DEVICE, Some(q), true).await.1;
    let mut q = saved.clone();
    q["phase"] = json!("bulk");
    q["weekly_loss_kg"] = json!(0.2);
    q["daily_steps_goal"] = json!(10000);
    q["finish_date"] = json!(chrono::Utc::now().date_naive() + chrono::Duration::days(28));
    let (status, bulk) = call(&db, DEVICE, Some(q.clone()), true).await;
    assert_eq!(status, 200);
    assert_ne!(bulk["id"], saved["id"]);
    assert_eq!(call(&db, DEVICE, Some(q), true).await.1["id"], bulk["id"]);
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES ('TEST-RELIABILITY','bulk-start',now()-interval '1 minute',64,'snoop','Test')").await;
    let response = call(&db, DEVICE, None, true).await.1;
    assert!(
        (response["summary"]["progress"]["target_weight_kg"]
            .as_f64()
            .unwrap()
            - 64.8)
            .abs()
            < 1e-8
    );
    let mut end = bulk.clone();
    end["active"] = json!(false);
    let (status, maintenance) = call(&db, DEVICE, Some(end.clone()), true).await;
    assert_eq!(status, 200);
    assert_eq!(maintenance["phase"], "maintenance");
    assert_eq!(maintenance["daily_steps_goal"], 7000);
    assert_eq!(maintenance["reminder_enabled"], true);
    assert!(maintenance["finish_date"].is_null());
    assert_eq!(
        call(&db, DEVICE, Some(end), true).await.1["id"],
        maintenance["id"]
    );
    let (_, closed) = history_call(&db, &format!("weight-goals/{}", bulk["id"])).await;
    assert_eq!(closed["goal"]["phase"], "bulk");
    assert!(
        (closed["summary"]["progress"]["target_weight_kg"]
            .as_f64()
            .unwrap()
            - 64.8)
            .abs()
            < 1e-8
    );
    assert_eq!(
        db.count("SELECT count(*) FROM weight_goal_history").await,
        2
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn maintenance_reference_is_learned_once_and_steps_do_not_reset_pace() {
    let db = Db::new().await;
    call(&db, DEVICE, None, true).await;
    db.sql("ALTER TABLE weight_goals DISABLE TRIGGER weight_goal_period;
      UPDATE weight_goals SET started_at=date_trunc('week',now())-interval '28 days',pace_started_at=date_trunc('week',now())-interval '28 days',timezone='UTC';
      ALTER TABLE weight_goals ENABLE TRIGGER weight_goal_period;
      INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name)
      SELECT 'TEST-RELIABILITY','anchor-'||i,(SELECT started_at FROM weight_goals)+i*interval '1 day',64,'snoop','Test' FROM generate_series(0,6) i").await;
    let first = call(&db, DEVICE, None, true).await.1;
    assert_eq!(first["goal"]["maintenance_reference_kg"], 64.0);
    db.sql("UPDATE weight_readings SET kg=70").await;
    let second = call(&db, DEVICE, None, true).await.1;
    assert_eq!(second["goal"], first["goal"]);
    let mut q = second["goal"].clone();
    q["daily_steps_goal"] = json!(8500);
    let next = call(&db, DEVICE, Some(q), true).await.1;
    assert_eq!(next["pace_started_at"], first["goal"]["pace_started_at"]);
    let mut q = next.clone();
    q["maintenance_reference_kg"] = json!(65);
    let revised = call(&db, DEVICE, Some(q), true).await.1;
    assert_ne!(revised["pace_started_at"], next["pace_started_at"]);
    assert_eq!(revised["started_at"], next["started_at"]);
    for (key, value) in [
        ("phase", json!("invalid")),
        ("maintenance_range_pct", json!(0)),
        ("maintenance_reference_kg", json!(2)),
    ] {
        let mut q = revised.clone();
        q[key] = value;
        assert_eq!(call(&db, DEVICE, Some(q), true).await.0, 400);
    }
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn legacy_clients_cannot_replace_a_non_cut_phase() {
    let db = Db::new().await;
    let goal = call(&db, DEVICE, None, true).await.1["goal"].clone();
    let mut legacy = input();
    legacy["revision"] = goal["revision"].clone();
    assert_eq!(call(&db, DEVICE, Some(legacy), true).await.0, 409);
    let current = call(&db, DEVICE, None, true).await.1["goal"].clone();
    assert_eq!(current["id"], goal["id"]);
    assert_eq!(current["phase"], "maintenance");
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn phase_migration_preserves_active_cut_and_converts_only_inactive_goal() {
    for active in [true, false] {
        let db = Db::new().await;
        // Rehearse the exact previous-column boundary in an isolated schema.
        db.sql("ALTER TABLE weight_goals DROP COLUMN phase CASCADE;
            ALTER TABLE weight_goals DROP COLUMN maintenance_reference_kg;
            ALTER TABLE weight_goals DROP COLUMN maintenance_range_pct;
            ALTER TABLE weight_goals ADD CONSTRAINT weight_goals_weekly_loss_kg_check CHECK(weekly_loss_kg BETWEEN 0.1 AND 1);").await;
        db.sql(&format!("INSERT INTO weight_goals(device_id,revision,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,updated_at,finish_date,daily_steps_goal)
          VALUES('TEST-RELIABILITY',1,{active},now()-interval '7 days',now()-interval '7 days','UTC',0.3,true,1,1200,now(),current_date+28,8000);
          INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(w) FROM weight_goals w;")).await;
        let original = db.count("SELECT id FROM weight_goals").await;
        db.raw(1).await;
        db.sql(include_str!("../../../migrations/0019_weight_phases.sql"))
            .await;
        let goal = call(&db, DEVICE, None, true).await.1["goal"].clone();
        assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
        assert_eq!(
            db.count("SELECT count(*) FROM weight_goal_history").await,
            0
        );
        assert_eq!(goal["active"], true);
        if active {
            assert_eq!(goal["id"], original);
            assert_eq!(goal["revision"], 1);
            assert_eq!(goal["phase"], "cut");
            assert_eq!(goal["daily_steps_goal"], 8000);
            assert_eq!(goal["weekly_loss_kg"], 0.3);
        } else {
            assert_ne!(goal["id"], original);
            assert_eq!(goal["revision"], 2);
            assert_eq!(goal["phase"], "maintenance");
            assert!(goal["finish_date"].is_null());
            assert!(goal["daily_steps_goal"].is_null());
        }
    }
}
