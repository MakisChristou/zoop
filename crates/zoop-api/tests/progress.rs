//! Bounded calendar windows, effective corrections and coverage contracts.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::Value;
use support::{DEVICE, Db, day};
use tower::ServiceExt;
use zoop_api::{AppState, build_router};
async fn fixture() -> Db {
    let db = Db::new().await;
    db.sql("INSERT INTO day_summary_cache(device_id,tz,day,start_ts,end_ts,dirty,samples,steps_walking,walking_s) SELECT 'TEST-RELIABILITY','UTC', '2025-01-01'::date+n,('2025-01-01'::date+n)::timestamp AT TIME ZONE 'UTC',('2025-01-02'::date+n)::timestamp AT TIME ZONE 'UTC',false,80000,CASE WHEN n<28 THEN 6000 ELSE 8000 END,1200 FROM generate_series(0,55)n").await;
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics) SELECT 'TEST-RELIABILITY','2025-01-01T00:00:00Z'::timestamptz+make_interval(days=>n),'2025-01-01T08:00:00Z'::timestamptz+make_interval(days=>n),'main','main','UTC',true,jsonb_build_object('sleep',jsonb_build_object('window',jsonb_build_object('asleep_s',CASE WHEN n<28 THEN 25200 ELSE 27000 END,'coverage_s',28800))) FROM generate_series(0,55)n").await;
    db.sql("INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone) SELECT 'TEST-RELIABILITY','2025-01-01T12:00:00Z'::timestamptz+make_interval(days=>n),'2025-01-01T13:00:00Z'::timestamptz+make_interval(days=>n),'resistance','resistance','UTC' FROM generate_series(0,55)n WHERE n%7=0 OR n%7=3").await;
    db
}
async fn result(db: &Db) -> Value {
    serde_json::to_value(
        zoop_core::progress(&db.store, DEVICE, day("2025-02-26"), "UTC")
            .await
            .unwrap()
            .unwrap(),
    )
    .unwrap()
}
async fn get(db: &Db, device: &str, tz: &str, auth: bool) -> (u16, Value) {
    let mut request = Request::get(format!("/v1/devices/{device}/progress?tz={tz}"));
    if auth {
        request = request.header("authorization", "Bearer test-token");
    }
    let response = build_router(AppState::new(db.store.clone(), "test-token".into()))
        .oneshot(request.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = to_bytes(response.into_body(), 100000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn effective_sleep_workouts_and_missing_weeks() {
    let db = fixture().await;
    let r = result(&db).await;
    assert_eq!(r["metrics"][0]["change"], 1800.0);
    assert_eq!(r["metrics"][2]["change"], 2000.0);
    assert_eq!(r["metrics"][4]["current"], 2.0);
    // Corrected main sleep wins over a detector candidate on the same local day.
    db.sql("UPDATE sleep_sessions SET metrics=jsonb_set(metrics,'{sleep,window,asleep_s}','25200') WHERE start_ts>='2025-01-29'; INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,metrics) VALUES('TEST-RELIABILITY','2025-02-01T00:00:00Z','2025-02-01T09:00:00Z','main','main','UTC','{\"sleep\":{\"window\":{\"asleep_s\":32400,\"coverage_s\":32400}}}'); UPDATE workout_sessions SET kind='walk' WHERE start_ts>='2025-01-29'").await;
    let r = result(&db).await;
    assert_eq!(r["metrics"][0]["change"], 0.0);
    assert_eq!(r["metrics"][4]["current"], 0.0);
    db.sql("UPDATE day_summary_cache SET samples=100 WHERE day='2025-02-01'; UPDATE sleep_sessions SET metrics_pending=true WHERE start_ts>='2025-01-29'").await;
    let r = result(&db).await;
    assert_eq!(r["metrics"][2]["current_count"], 27);
    assert_eq!(r["metrics"][3]["current_count"], 3);
    assert!(r["metrics"][0]["change"].is_null());
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn auth_zone_unknown_device_and_empty_history() {
    let db = Db::new().await;
    assert_eq!(get(&db, DEVICE, "UTC", false).await.0, 401);
    assert_eq!(get(&db, DEVICE, "Invalid/Zone", true).await.0, 400);
    assert_eq!(get(&db, "UNKNOWN", "UTC", true).await.0, 404);
    let (status, r) = get(&db, DEVICE, "UTC", true).await;
    assert_eq!(status, 200);
    assert!(r["metrics"][2]["current"].is_null());
    assert_eq!(r["metrics"][2]["weeks"].as_array().unwrap().len(), 8);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn local_dst_days_and_removed_sessions() {
    let db = fixture().await;
    let rows = db
        .store
        .progress_days(
            DEVICE,
            day("2025-03-30"),
            day("2025-03-31"),
            "Europe/Berlin",
            zoop_analytics::WORKOUT_ALGO_VERSION,
        )
        .await
        .unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].day_seconds, 82800.0);
    db.sql("UPDATE workout_sessions SET status='removed' WHERE start_ts>='2025-01-29'; UPDATE sleep_sessions SET status='removed' WHERE start_ts>='2025-01-29'").await;
    let r = result(&db).await;
    assert!(r["metrics"][0]["current"].is_null());
    assert_eq!(r["metrics"][4]["current"], 0.0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn superseded_jobs_do_not_hide_strength_but_current_jobs_do() {
    let db = fixture().await;
    let version = zoop_analytics::WORKOUT_ALGO_VERSION;
    for v in [version - 1, version] {
        sqlx::query("INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version) VALUES($1,'workout','2025-02-01','UTC',$2)")
            .bind(DEVICE).bind(v).execute(&db.pool).await.unwrap();
        let r = result(&db).await;
        assert_eq!(
            r["metrics"][4]["current_count"],
            if v == version { 3 } else { 4 }
        );
    }
}
