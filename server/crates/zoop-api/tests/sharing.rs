//! End-to-end authorization tests against isolated development database schemas.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};

use serde_json::{Value, json};
use support::Db;
use tower::ServiceExt;
use zoop_api::{AppState, WebOptions, build_router};
use zoop_auth::{digest, hash_password};
const ORIGIN: &str = "https://zoop.example";
const PASSWORD: &str = "test-only strong password";
fn router(db: &Db) -> Router {
    build_router(
        AppState::new(db.store.clone(), "legacy-global-token".into()).with_web(WebOptions {
            origin: ORIGIN.into(),
            secure_cookie: true,
        }),
    )
}
async fn req(
    app: &Router,
    method: &str,
    path: &str,
    cookie: Option<&str>,
    bearer: Option<&str>,
    body: Value,
) -> (StatusCode, Value, Option<String>) {
    let mut r = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json")
        .header("origin", ORIGIN);
    if let Some(c) = cookie {
        r = r.header("cookie", c);
    }
    if let Some(t) = bearer {
        r = r.header("authorization", format!("Bearer {t}"));
    }
    let response = app
        .clone()
        .oneshot(r.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let cookie = response
        .headers()
        .get("set-cookie")
        .map(|v| v.to_str().unwrap().to_owned());
    let bytes = to_bytes(response.into_body(), 1_000_000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        cookie,
    )
}
async fn setup() -> (Db, Router, String, String) {
    let db = Db::new().await;
    let hash = hash_password(PASSWORD).unwrap();
    db.store
        .create_account("owner@example.test", &hash, true)
        .await
        .unwrap();
    db.store
        .create_account("member@example.test", &hash, false)
        .await
        .unwrap();
    db.store
        .bind_account_device("owner@example.test", support::DEVICE)
        .await
        .unwrap();
    db.store
        .bind_account_device("member@example.test", "OTHER")
        .await
        .unwrap();
    db.store.upsert_device("OTHER", "TEST", None).await.unwrap();
    db.store
        .add_account_token("owner@example.test", &digest("owner-phone-token"))
        .await
        .unwrap();
    let app = router(&db);
    let owner = login(&app, "owner@example.test").await;
    let member = login(&app, "member@example.test").await;
    (db, app, owner, member)
}
async fn login(app: &Router, email: &str) -> String {
    let (status, _, cookie) = req(
        app,
        "POST",
        "/v1/auth/login",
        None,
        None,
        json!({"email":email,"password":PASSWORD}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let raw = cookie.unwrap();
    assert!(raw.contains("HttpOnly") && raw.contains("Secure") && raw.contains("SameSite=Strict"));
    raw.split(';').next().unwrap().to_owned()
}

fn input(keys: Value) -> Value {
    json!({"device_id":support::DEVICE,"config":{"title":"Training","range":"all","widgets":keys},"expires_at":null})
}
async fn visit(
    app: &Router,
    token: &str,
    password: &str,
    year: Option<i32>,
) -> (StatusCode, Value, Option<String>) {
    req(
        app,
        "POST",
        "/v1/public/dashboard",
        None,
        None,
        json!({"token":token,"password":password,"year":year}),
    )
    .await
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn links_are_scoped_revocable_and_never_account_credentials() {
    let (db, app, owner, member) = setup().await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','w','2025-01-01T12:00:00Z',70,'health','private source'),('OTHER','w','2025-01-01T12:00:00Z',99,'health','private source')").await;
    let (status, created, _) = req(
        &app,
        "POST",
        "/v1/shares",
        Some(&owner),
        None,
        input(json!(["weight"])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    let token = created["token"].as_str().unwrap();
    let id = created["id"].as_i64().unwrap();
    assert!(created.get("password_hash").is_none());
    let path = format!("/v1/shares/{id}");
    let (_, other, _) = req(&app, "GET", "/v1/shares", Some(&member), None, Value::Null).await;
    assert_eq!(other, json!([]));
    assert_eq!(
        req(&app, "DELETE", &path, Some(&member), None, Value::Null)
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(
            &app,
            "PUT",
            &path,
            Some(&member),
            None,
            input(json!(["weight"]))
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/shares",
            Some(&member),
            None,
            input(json!(["weight"]))
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", None, Some(token), Value::Null)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    let (status, data, _) = visit(&app, token, "", Some(2025)).await;
    assert_eq!(status, StatusCode::OK, "{data}");
    assert_eq!(data["widgets"][0]["points"][0]["value"], 70.0);
    let public = data.to_string();
    for private in [
        "device_id",
        "account_id",
        "password",
        "token",
        "source_name",
        "private source",
        "email",
        "99.0",
    ] {
        assert!(!public.contains(private), "{private}: {public}");
    }
    assert!(data["photo"].is_null());
    assert_eq!(data["widgets"].as_array().unwrap().len(), 1);
    let mut edit = created.clone();
    edit.as_object_mut().unwrap().retain(|k, _| {
        ["device_id", "config", "enabled", "expires_at", "revision"].contains(&k.as_str())
    });
    edit["enabled"] = json!(false);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit.clone())
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(visit(&app, token, "", None).await.0, StatusCode::NOT_FOUND);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit.clone())
            .await
            .0,
        StatusCode::CONFLICT
    );
    edit["revision"] = json!(2);
    edit["enabled"] = json!(true);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit).await.0,
        StatusCode::OK
    );
    db.sql("UPDATE accounts SET enabled=false WHERE email='owner@example.test'")
        .await;
    assert_eq!(visit(&app, token, "", None).await.0, StatusCode::NOT_FOUND);
    db.sql("UPDATE accounts SET enabled=true WHERE email='owner@example.test'; DELETE FROM device_owners WHERE device_id='TEST-RELIABILITY'").await;
    assert_eq!(visit(&app, token, "", None).await.0, StatusCode::NOT_FOUND);
    assert_eq!(
        req(&app, "DELETE", &path, Some(&owner), None, Value::Null)
            .await
            .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(visit(&app, token, "", None).await.0, StatusCode::NOT_FOUND);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn passwords_expiry_csrf_and_limits() {
    let (_db, app, owner, _) = setup().await;
    let mut body = input(json!(["steps"]));
    body["password"] = json!("share-only password");
    let (status, s, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    let token = s["token"].as_str().unwrap();
    assert_eq!(
        visit(&app, token, "", None).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        visit(&app, token, "wrong", None).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        visit(&app, token, "share-only password", None).await.0,
        StatusCode::OK
    );
    let request = Request::builder()
        .method("POST")
        .uri("/v1/shares")
        .header("content-type", "application/json")
        .header("origin", "https://attacker.example")
        .header("cookie", &owner)
        .body(Body::from(body.to_string()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(request).await.unwrap().status(),
        StatusCode::FORBIDDEN
    );
    body["expires_at"] = json!("2020-01-01T00:00:00Z");
    let (_, expired, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
    assert_eq!(
        visit(
            &app,
            expired["token"].as_str().unwrap(),
            "share-only password",
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    body["config"]["widgets"] = json!(["raw_frames"]);
    assert_eq!(
        req(&app, "POST", "/v1/shares", Some(&owner), None, body)
            .await
            .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(visit(&app, "bad", "", None).await.0, StatusCode::NOT_FOUND);
    for _ in 0..28 {
        let _ = visit(&app, token, "wrong", None).await;
    }
    assert_eq!(
        visit(&app, token, "share-only password", None).await.0,
        StatusCode::TOO_MANY_REQUESTS
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn each_projection_uses_only_selected_daily_metric() {
    let (db, app, owner, _) = setup().await;
    db.sql(r#"INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','old','2020-01-01T12:00:00Z',72,'health','synthetic'),('TEST-RELIABILITY','w','2025-01-01T12:00:00Z',70,'health','synthetic'),('TEST-RELIABILITY','manual','2025-01-01T15:00:00Z',71,'snoop','synthetic');
 INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics) VALUES('TEST-RELIABILITY','2025-01-01T00:00:00Z','2025-01-01T08:00:00Z','main','main','UTC',true,'{"sleep":{"window":{"asleep_s":28800},"physiology":{"hrv_rmssd_ms":55,"resting_hr":48}}}');
 INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind) VALUES('TEST-RELIABILITY','2025-01-01T12:00:00Z','2025-01-01T13:00:00Z','resistance','resistance');
 INSERT INTO strains(device_id,day,algo_version,load) VALUES('TEST-RELIABILITY','2025-01-01',1,8);
 INSERT INTO recovery_observations(device_id,day,tz,formula_version,input_fingerprint,inputs,result) VALUES('TEST-RELIABILITY','2025-01-01','UTC',1,'synthetic','{}','{"score":65}');"#).await;
    let raw = db.raw(1).await;
    for (n, steps, activity) in [(0, 100, 1), (1, 105, 1), (2, 110, 0)] {
        let mut s = support::sample(
            raw,
            support::at("2025-01-01T10:00:00Z") + chrono::Duration::seconds(n),
        );
        s.steps = Some(steps);
        s.activity = Some(activity);
        db.store.upsert_sample(&s).await.unwrap();
    }
    db.store
        .shared_earliest(support::DEVICE, "UTC", &["weight".into()])
        .await
        .unwrap();
    for key in [
        "sleep",
        "load",
        "steps",
        "workouts",
        "weight",
        "hrv",
        "resting_hr",
    ] {
        db.store
            .shared_points(
                support::DEVICE,
                "UTC",
                support::day("2025-01-01"),
                support::day("2025-12-31"),
                key,
                1,
            )
            .await
            .unwrap_or_else(|e| panic!("{key}: {e:?}"));
    }
    let body = input(json!([
        "sleep",
        "recovery",
        "load",
        "steps",
        "workouts",
        "weight",
        "hrv",
        "resting_hr"
    ]));
    let (status, s, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, body).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    let token = s["token"].as_str().unwrap();
    let (status, data, _) = visit(&app, token, "", Some(2025)).await;
    assert_eq!(status, StatusCode::OK, "{data}");
    let actual = data["widgets"].as_array().unwrap();
    for (key, value) in [
        ("sleep", 28800.0),
        ("load", 8.0),
        ("steps", 5.0),
        ("workouts", 1.0),
        ("weight", 70.0),
        ("hrv", 55.0),
        ("resting_hr", 48.0),
    ] {
        let w = actual.iter().find(|w| w["key"] == key).unwrap();
        let p = w["points"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["day"] == "2025-01-01")
            .unwrap();
        assert_eq!(p["value"].as_f64(), Some(value), "{key}: {p}");
    }
    assert!(data["widgets"][1]["points"][0]["value"].is_null());
    assert_eq!(data["first_year"], 2020);
    assert_eq!(data["from"], "2025-01-01");
    assert_eq!(data["to"], "2025-12-31");
    assert_eq!(
        visit(&app, token, "", Some(2019)).await.0,
        StatusCode::NOT_FOUND
    );
    let (status, old, _) = visit(&app, token, "", Some(2020)).await;
    assert_eq!(status, StatusCode::OK, "{old}");
    assert_eq!(old["widgets"][5]["points"][0]["value"], 72.0);
    db.sql("UPDATE sleep_sessions SET metrics_pending=true")
        .await;
    let (_, data, _) = visit(&app, token, "", Some(2025)).await;
    assert!(data["widgets"][0]["points"][0]["value"].is_null());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn defaults_date_windows_and_password_edits_are_enforced_server_side() {
    let (db, app, owner, _) = setup().await;
    db.sql("INSERT INTO profiles(device_id,tz) VALUES('TEST-RELIABILITY','America/New_York'); INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','before','2025-03-09T04:30:00Z',70,'health','synthetic'),('TEST-RELIABILITY','after','2025-03-09T07:30:00Z',69,'health','synthetic'),('TEST-RELIABILITY','other','2025-03-10T04:30:00Z',68,'health','synthetic')").await;
    let body =
        json!({"device_id":support::DEVICE,"config":{"title":"Weights","widgets":["weight"]}});
    let (status, s, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, body).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["config"]["range"], "last30");
    assert!(!s["expires_at"].is_null());
    let (status, data, _) = visit(&app, s["token"].as_str().unwrap(), "", Some(2025)).await;
    assert_eq!(status, StatusCode::OK, "{data}");
    assert_eq!(
        (support::day(data["to"].as_str().unwrap()) - support::day(data["from"].as_str().unwrap()))
            .num_days(),
        29
    );
    assert_eq!(data["paged"], false);
    assert!(data["widgets"][0]["points"].as_array().unwrap().is_empty());
    let path = format!("/v1/shares/{}", s["id"]);
    let mut edit = json!({"device_id":support::DEVICE,"config":{"title":"Weights","range":"fixed","from":"2025-03-09","to":"2025-03-09","widgets":["weight"]},"password":"new share password","revision":1,"expires_at":null});
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit.clone())
            .await
            .0,
        StatusCode::OK
    );
    let token = s["token"].as_str().unwrap();
    assert_eq!(
        visit(&app, token, "", None).await.0,
        StatusCode::UNAUTHORIZED
    );
    let (_, data, _) = visit(&app, token, "new share password", Some(2020)).await;
    assert_eq!(
        data["widgets"][0]["points"],
        json!([{"day":"2025-03-09","value":69}])
    );
    edit["revision"] = json!(2);
    edit.as_object_mut().unwrap().remove("password");
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit.clone())
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(
        visit(&app, token, "", None).await.0,
        StatusCode::UNAUTHORIZED
    );
    edit["revision"] = json!(3);
    edit["password"] = json!("");
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, edit).await.0,
        StatusCode::OK
    );
    assert_eq!(visit(&app, token, "", None).await.0, StatusCode::OK);
    let huge = json!({"token":token,"password":"x".repeat(20000)});
    assert_eq!(
        req(&app, "POST", "/v1/public/dashboard", None, None, huge)
            .await
            .0,
        StatusCode::PAYLOAD_TOO_LARGE
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn rich_widgets_disclose_only_their_selected_fields_and_bounds() {
    let (db, app, owner, member) = setup().await;
    db.sql(r#"INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind,metrics) VALUES
 ('TEST-RELIABILITY','2025-01-02T12:00:00Z','2025-01-02T13:00:00Z','resistance','resistance','{"load":8.5,"avg_hr":123,"kcal":450,"steps":999}'),
 ('TEST-RELIABILITY','2025-01-02T15:00:00Z','2025-01-02T15:40:00Z','walk','walk','{"load":5.2,"avg_hr":110}'),
 ('TEST-RELIABILITY','2025-01-02T16:00:00Z','2025-01-02T16:40:00Z','walk','walk','{"load":4.1}'),
 ('TEST-RELIABILITY','2024-12-31T12:00:00Z','2024-12-31T13:00:00Z','resistance','resistance','{"load":9}'),
 ('OTHER','2025-01-02T12:00:00Z','2025-01-02T13:00:00Z','walk','walk','{"load":20}');
 INSERT INTO strains(device_id,day,algo_version,load) VALUES('TEST-RELIABILITY','2025-01-02',1,12);
 INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','old-weight','2020-01-01T00:00:00Z',70,'health','synthetic');"#).await;
    for key in [
        "activity_heatmap",
        "recent_workouts",
        "by_sport",
        "workouts",
    ] {
        let mut body = input(json!([key]));
        body["config"]["range"] = json!("fixed");
        body["config"]["from"] = json!("2025-01-01");
        body["config"]["to"] = json!("2025-01-03");
        let (status, s, _) =
            req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
        assert_eq!(status, StatusCode::OK, "{s}");
        let token = s["token"].as_str().unwrap();
        let (status, data, _) = visit(&app, token, "", Some(2020)).await;
        assert_eq!(status, StatusCode::OK, "{data}");
        let w = &data["widgets"][0];
        assert_eq!(w["key"], key);
        assert_eq!(data["from"], "2025-01-01");
        assert_eq!(data["first_year"], 2025);
        let serialized = data.to_string();
        for hidden in [
            "avg_hr",
            "kcal",
            "start_ts",
            "end_ts",
            "device_id",
            "detected_kind",
            "revision",
            "source_name",
            "2024-12-31",
            "old-weight",
        ] {
            assert!(
                !serialized.contains(hidden),
                "{key} leaks {hidden}: {serialized}"
            );
        }
        match key {
            "activity_heatmap" => {
                assert_eq!(w["points"][0]["value"].as_f64(), Some(12.0));
                let rows = w["activities"].as_array().unwrap();
                assert_eq!(rows.len(), 2);
                let walk = rows.iter().find(|r| r["kind"] == "walk").unwrap();
                assert_eq!(walk["count"], 2);
                assert_eq!(walk["duration_s"], 4800);
                assert!(walk.get("load").is_none());
                assert!(walk.get("id").is_none());
            }
            "recent_workouts" => {
                let rows = w["activities"].as_array().unwrap();
                assert_eq!(rows.len(), 3);
                assert_eq!(rows[0]["kind"], "walk");
                assert_eq!(rows[2]["duration_s"], 3600);
                assert_eq!(rows[2]["load"].as_f64(), Some(8.5));
                assert!(w.get("sports").is_none());
                assert!(rows[0].get("id").is_none());
            }
            "by_sport" => {
                assert_eq!(
                    w["sports"],
                    json!([{"kind":"walk","seconds":4800,"count":2},{"kind":"resistance","seconds":3600,"count":1}])
                );
                assert!(w.get("activities").is_none());
                assert!(w.get("points").is_none());
            }
            _ => {
                assert_eq!(w["points"][0]["value"], 3);
                assert!(w.get("activities").is_none());
            }
        }
        assert_eq!(
            req(
                &app,
                "POST",
                "/v1/shares/preview",
                Some(&member),
                None,
                json!({"device_id":support::DEVICE,"config":body["config"]})
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
    }
    db.sql("UPDATE workout_sessions SET metrics_pending=true WHERE kind='resistance'; UPDATE workout_sessions SET status='removed' WHERE start_ts='2025-01-02T16:00:00Z' AND device_id='TEST-RELIABILITY'").await;
    let rows = db
        .store
        .shared_activities(
            support::DEVICE,
            "UTC",
            support::day("2025-01-01"),
            support::day("2025-01-03"),
        )
        .await
        .unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["kind"], "walk");
    let earliest = db
        .store
        .shared_earliest(support::DEVICE, "UTC", &["by_sport".into()])
        .await
        .unwrap();
    assert_eq!(earliest, Some(support::day("2024-12-31")));
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn daily_rings_share_one_bounded_day_and_match_private_recovery() {
    let (db, app, owner, member) = setup().await;
    db.store
        .save_sleep_goal(support::DEVICE, 540, false, "UTC")
        .await
        .unwrap();
    let raw = db.raw(1).await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id) SELECT $1,'2025-01-01T06:00:00Z'::timestamptz+make_interval(days=>d,secs=>n),55,ARRAY[1000,1020],0,0,2,$2 FROM generate_series(0,19)d CROSS JOIN generate_series(0,3599)n").bind(support::DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    db.sql("INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics) SELECT 'TEST-RELIABILITY','2025-01-01T06:00:00Z'::timestamptz+make_interval(days=>d),'2025-01-01T07:00:00Z'::timestamptz+make_interval(days=>d),'main','main','UTC',true,jsonb_build_object('sleep',jsonb_build_object('algo_version',5,'window',jsonb_build_object('asleep_s',3600,'coverage_s',3600),'physiology',jsonb_build_object('resting_hr',55,'hrv_rmssd_ms',50,'hrv_windows',12))) FROM generate_series(0,19)d; INSERT INTO strains(device_id,day,algo_version,load) VALUES('TEST-RELIABILITY','2025-01-15',1,12)").await;
    let mut body = input(json!(["daily_rings"]));
    body["config"]["range"] = json!("fixed");
    body["config"]["from"] = json!("2025-01-14");
    body["config"]["to"] = json!("2025-01-15");
    body["config"]["layout"] = json!([{"key":"daily_rings","x":0,"y":2}]);
    let (status, share, _) =
        req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
    assert_eq!(status, StatusCode::OK, "{share}");
    let token = share["token"].as_str().unwrap();
    for pending in [false, true] {
        if pending {
            db.sql("UPDATE sleep_sessions SET metrics_pending=true WHERE end_ts='2025-01-15T07:00:00Z'").await;
        }
        let (status, data, _) = visit(&app, token, "", Some(2020)).await;
        assert_eq!(status, StatusCode::OK, "{data}");
        assert_eq!(data["layout"], body["config"]["layout"]);
        let ring = &data["widgets"][0];
        assert_eq!(ring["day"], "2025-01-15");
        assert_eq!(ring["sleep_goal_minutes"], 540);
        assert_eq!(ring["load"].as_f64(), Some(12.0));
        let private = zoop_core::morning_insights(
            &db.store,
            support::DEVICE,
            support::day("2025-01-15"),
            "UTC",
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(
            ring["recovery"],
            json!({"version":private.recovery.version,"method":private.recovery.method,"score":private.recovery.score,"band":private.recovery.band,"state":private.recovery.state})
        );
        if !pending {
            assert!(private.recovery.score.is_some());
            assert_eq!(ring["sleep_seconds"], 3600);
        } else {
            assert!(ring["sleep_seconds"].is_null());
        }
        for hidden in [
            "hrv_rmssd_ms",
            "resting_hr",
            "components",
            "limiting",
            "baseline_count",
            "device_id",
            "sleep_id",
        ] {
            assert!(!data.to_string().contains(hidden), "{hidden}");
        }
    }
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/shares/preview",
            Some(&member),
            None,
            json!({"device_id":support::DEVICE,"config":body["config"]})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    body["config"]["to"] = json!("2025-01-21");
    let (status, empty, _) = req(
        &app,
        "POST",
        "/v1/shares/preview",
        Some(&owner),
        None,
        json!({"device_id":support::DEVICE,"config":body["config"]}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{empty}");
    assert!(empty["widgets"][0]["sleep_seconds"].is_null());
    assert!(empty["widgets"][0]["load"].is_null());
    body["config"]["layout"][0]["x"] = json!(1);
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/shares/preview",
            Some(&owner),
            None,
            json!({"device_id":support::DEVICE,"config":body["config"]})
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn heatmap_year_expands_only_the_explicitly_selected_widget() {
    let (db, app, owner, _) = setup().await;
    db.sql(r#"INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind,metrics) VALUES
    ('TEST-RELIABILITY','2023-12-01T12:00:00Z','2023-12-01T13:00:00Z','walk','walk','{"load":4}'),
    ('TEST-RELIABILITY','2024-12-01T12:00:00Z','2024-12-01T13:00:00Z','walk','walk','{"load":5}'),
    ('TEST-RELIABILITY','2025-01-02T12:00:00Z','2025-01-02T13:00:00Z','walk','walk','{"load":6}');
    INSERT INTO strains(device_id,day,algo_version,load) VALUES
    ('TEST-RELIABILITY','2023-12-01',1,4),('TEST-RELIABILITY','2024-12-01',1,5),('TEST-RELIABILITY','2025-01-02',1,6);"#).await;
    let mut body = input(json!(["activity_heatmap", "recent_workouts", "load"]));
    body["config"]["range"] = json!("fixed");
    body["config"]["from"] = json!("2025-01-01");
    body["config"]["to"] = json!("2025-01-03");
    for expanded in [false, true, false] {
        body["config"]["heatmap_year"] = json!(expanded);
        let (status, share, _) =
            req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
        assert_eq!(status, StatusCode::OK, "{share}");
        let (_, data, _) = visit(&app, share["token"].as_str().unwrap(), "", Some(2023)).await;
        assert_eq!(data["from"], "2025-01-01");
        let heat = &data["widgets"][0];
        assert_eq!(
            heat["activities"].as_array().unwrap().len(),
            if expanded { 2 } else { 1 }
        );
        assert_eq!(
            heat["points"].as_array().unwrap().len(),
            if expanded { 2 } else { 1 }
        );
        assert_eq!(
            heat["from"],
            if expanded { "2024-01-05" } else { "2025-01-01" }
        );
        assert_eq!(heat["to"], "2025-01-03");
        assert_eq!(
            data["widgets"][1]["activities"].as_array().unwrap().len(),
            1
        );
        assert_eq!(data["widgets"][2]["points"].as_array().unwrap().len(), 1);
        assert!(!data.to_string().contains("2023-12-01"));
        assert_eq!(data.to_string().contains("2024-12-01"), expanded);
    }
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sleep_goal_is_owned_validated_and_preserved_by_legacy_profile_saves() {
    let (db, app, owner, member) = setup().await;
    let path = format!("/v1/devices/{}/sleep-goal", support::DEVICE);
    let (status, goal, _) = req(&app, "GET", &path, Some(&owner), None, json!(null)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(goal, json!({"minutes":480,"configured":false}));
    assert_eq!(
        req(&app, "GET", &path, Some(&member), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", &path, None, None, json!(null)).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        req(
            &app,
            "PUT",
            "/v1/devices/OTHER/sleep-goal",
            None,
            Some("owner-phone-token"),
            json!({"minutes":540})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    for minutes in [0, 59, 61, 1441, 1500] {
        assert_eq!(
            req(
                &app,
                "PUT",
                &path,
                None,
                Some("owner-phone-token"),
                json!({"minutes":minutes})
            )
            .await
            .0,
            StatusCode::BAD_REQUEST
        );
    }
    let (status, goal, _) = req(
        &app,
        "PUT",
        &path,
        None,
        Some("owner-phone-token"),
        json!({"minutes":540,"initialize_only":true,"tz":"Pacific/Auckland"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(goal, json!({"minutes":540,"configured":true}));
    assert_eq!(db.count("SELECT count(*) FROM analysis_jobs").await, 0);
    assert_eq!(db.count("SELECT count(*) FROM profile_revisions").await, 0);
    let (_, goal, _) = req(
        &app,
        "PUT",
        &path,
        None,
        Some("owner-phone-token"),
        json!({"minutes":420,"initialize_only":true,"tz":"UTC"}),
    )
    .await;
    assert_eq!(goal["minutes"], 540);
    assert_eq!(
        db.store
            .get_profile(support::DEVICE)
            .await
            .unwrap()
            .unwrap()
            .tz,
        "Pacific/Auckland"
    );
    let (_, goal, _) = req(
        &app,
        "PUT",
        &path,
        None,
        Some("owner-phone-token"),
        json!({"minutes":600}),
    )
    .await;
    assert_eq!(goal["minutes"], 600);
    let profile_path = format!("/v1/devices/{}/profile", support::DEVICE);
    assert_eq!(
        req(
            &app,
            "PUT",
            &profile_path,
            None,
            Some("owner-phone-token"),
            json!({"height_cm":180,"tz":"UTC"})
        )
        .await
        .0,
        StatusCode::OK
    );
    let (_, goal, _) = req(&app, "GET", &path, Some(&owner), None, json!(null)).await;
    assert_eq!(goal["minutes"], 600);
    // Browser health writes remain disallowed; this slice only renders the goal there.
    assert_eq!(
        req(
            &app,
            "PUT",
            &path,
            Some(&owner),
            None,
            json!({"minutes":480})
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn concurrent_sleep_goal_migration_keeps_the_first_saved_target() {
    let db = Db::new().await;
    let (a, b) = tokio::join!(
        db.store.save_sleep_goal(support::DEVICE, 540, true, "UTC"),
        db.store.save_sleep_goal(support::DEVICE, 600, true, "UTC"),
    );
    let a = a.unwrap();
    let b = b.unwrap();
    assert_eq!(a.minutes, b.minutes);
    assert_eq!(
        db.store.sleep_goal(support::DEVICE).await.unwrap().minutes,
        a.minutes
    );
}

#[tokio::test]
#[ignore = "requires ZOOP_TEST_DATABASE_URL"]
async fn private_layouts_are_owned_versioned_validated_and_not_public() {
    let (db, app, owner, member) = setup().await;
    let path = format!("/v1/dashboard-layouts/{}", support::DEVICE);
    let config = json!({"title":"My dashboard","widgets":["weight","sleep"],"layout":[{"key":"weight","x":0,"y":0,"size":"wide"},{"key":"sleep","x":0,"y":4}]});
    let (status, empty, _) = req(&app, "GET", &path, Some(&owner), None, Value::Null).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(empty, json!({"config":null,"revision":0}));
    for method in ["GET", "PUT"] {
        let (status, _, _) = req(
            &app,
            method,
            &path,
            Some(&member),
            None,
            json!({"config":config,"revision":0}),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
    }
    let input = json!({"config":config,"revision":0});
    let (status, saved, _) = req(&app, "PUT", &path, Some(&owner), None, input.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(saved["revision"], 1);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, input.clone())
            .await
            .0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        req(&app, "GET", &path, Some(&owner), None, Value::Null)
            .await
            .1,
        saved
    );
    assert_eq!(db.count("SELECT count(*) FROM shared_dashboards").await, 0);
    let mut bad = input.clone();
    bad["revision"] = json!(1);
    bad["config"]["layout"][1]["y"] = json!(0);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, bad).await.0,
        StatusCode::BAD_REQUEST
    );
    let mut bad = input.clone();
    bad["config"]["layout"][0]["size"] = json!("huge");
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, bad).await.0,
        StatusCode::BAD_REQUEST
    );
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(&path)
                .header("content-type", "application/json")
                .header("origin", "https://attacker.example")
                .header("cookie", &owner)
                .body(Body::from(input.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    assert_eq!(
        req(
            &app,
            "GET",
            &path,
            None,
            Some("owner-phone-token"),
            Value::Null
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        req(&app, "GET", &path, None, None, Value::Null).await.0,
        StatusCode::UNAUTHORIZED
    );
    let mut next = input;
    next["revision"] = json!(1);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, next).await.1["revision"],
        2
    );
    db.sql("DELETE FROM device_owners WHERE device_id='TEST-RELIABILITY'")
        .await;
    assert_eq!(db.count("SELECT count(*) FROM dashboard_layouts").await, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn complete_widget_catalog_is_opt_in_bounded_and_matches_private_measurements() {
    let (db, app, owner, member) = setup().await;
    db.sql(r#"INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics)
      VALUES('TEST-RELIABILITY','2025-01-15T00:00:00Z','2025-01-15T08:00:00Z','main','main','UTC',true,
      '{"private_marker":"never-share","sleep":{"algo_version":5,"partial":false,"window":{"asleep_s":28000,"coverage_s":28800,"efficiency":0.97,"onset":"2025-01-15T00:00:00Z","offset":"2025-01-15T08:00:00Z"},"stages":{"deep_s":7200,"rem_s":7200,"light_s":13600,"wake_s":800},"physiology":{"resting_hr":48,"hrv_rmssd_ms":81,"hrv_windows":96,"respiratory_rate":13,"secret_field":999},"segments":[{"stage":"deep","start":"2025-01-15T01:00:00Z","end":"2025-01-15T03:00:00Z","private_marker":"hidden"}]}}');
      INSERT INTO weight_goals(device_id,phase,active,started_at,pace_started_at,timezone,weekly_loss_kg,reminder_enabled,reminder_weekday,reminder_minute,maintenance_reference_kg,revision,updated_at) VALUES('TEST-RELIABILITY','maintenance',true,'2025-01-01','2025-01-01','UTC',0,false,1,1200,70,1,'2025-01-01');
      INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','old','2025-01-01T12:00:00Z',70,'health','private source'),('TEST-RELIABILITY','inside','2025-01-15T12:00:00Z',69,'health','private source'),('TEST-RELIABILITY','future','2025-01-16T12:00:00Z',68,'health','private source');"#).await;
    let keys = [
        "recovery",
        "sleep_timeline",
        "sleep_stages",
        "nightly_metrics",
        "morning_outlook",
        "goal_progress",
        "goal_weight",
    ];
    for key in keys {
        let mut body = input(json!([key]));
        body["config"]["range"] = json!("fixed");
        body["config"]["from"] = json!("2025-01-15");
        body["config"]["to"] = json!("2025-01-15");
        let (status, created, _) =
            req(&app, "POST", "/v1/shares", Some(&owner), None, body.clone()).await;
        assert_eq!(status, StatusCode::OK, "{key}: {created}");
        let (status, public, _) = visit(&app, created["token"].as_str().unwrap(), "", None).await;
        assert_eq!(status, StatusCode::OK, "{key}: {public}");
        let (_, preview, _) = req(
            &app,
            "POST",
            "/v1/shares/preview",
            Some(&owner),
            None,
            json!({"device_id":support::DEVICE,"config":body["config"]}),
        )
        .await;
        assert_eq!(preview, public, "{key} preview parity");
        assert_eq!(public["widgets"].as_array().unwrap().len(), 1);
        let text = public.to_string();
        for hidden in [
            "private_marker",
            "secret_field",
            "private source",
            "device_id",
            "session_id",
            "reminder_minute",
            "revision",
            "2025-01-16",
        ] {
            assert!(!text.contains(hidden), "{key} leaked {hidden}");
        }
        let w = &public["widgets"][0];
        match key {
            "recovery" => {
                assert!(w["points"][0]["recovery"].is_object());
                assert!(!text.contains("hrv_ms"));
                assert!(!text.contains("resting_hr"));
            }
            "sleep_timeline" => {
                assert_eq!(w["night"]["sleep"]["segments"].as_array().unwrap().len(), 1);
                assert!(!text.contains("physiology"));
                assert!(!text.contains("deep_s"));
            }
            "sleep_stages" => {
                assert_eq!(w["night"]["sleep"]["stages"]["deep_s"], 7200);
                assert!(!text.contains("segments"));
            }
            "nightly_metrics" => {
                assert_eq!(w["metrics"]["hrv_rmssd_ms"], 81);
                assert_eq!(w["metrics"]["efficiency"], 0.97);
                assert!(!text.contains("segments"));
            }
            "goal_weight" => {
                assert_eq!(
                    w["summary"]["progress"]["weigh_ins"],
                    json!([{"day":"2025-01-15","kg":69.0}])
                );
                assert!(w["goal"].get("id").is_none());
            }
            "goal_progress" => {
                assert_eq!(w["summary"]["progress"]["total_lost_kg"], 1.0);
                assert_eq!(w["summary"]["progress"]["weigh_ins"], json!([]));
            }
            _ => {}
        }
        assert_eq!(
            req(
                &app,
                "POST",
                "/v1/shares/preview",
                Some(&member),
                None,
                json!({"device_id":support::DEVICE,"config":body["config"]})
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
    }
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn completed_sleep_survives_routine_queue_but_corrections_show_loading() {
    let (db, app, owner, _) = setup().await;
    db.sql(r#"INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics)
      VALUES('TEST-RELIABILITY','2025-01-15T00:00:00Z','2025-01-15T08:00:00Z','main','main','UTC',true,'{"sleep":{"window":{"asleep_s":28000}}}');
      INSERT INTO sleep_evidence(session_id,revision,boundary_complete,hr_samples) SELECT id,revision,true,28800 FROM sleep_sessions;
      INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,generation,completed_generation) VALUES('TEST-RELIABILITY','sleep','2025-01-15','UTC',5,2,1);"#).await;
    let mut c = input(json!(["daily_rings"]));
    c["config"]["range"] = json!("fixed");
    c["config"]["from"] = json!("2025-01-15");
    c["config"]["to"] = json!("2025-01-15");
    let (_, share, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, c).await;
    let token = share["token"].as_str().unwrap();
    let (_, d, _) = visit(&app, token, "", None).await;
    assert_eq!(d["widgets"][0]["sleep_seconds"], 28000);
    assert_eq!(d["widgets"][0]["sleep_state"], "ready");
    db.sql("UPDATE sleep_sessions SET metrics_pending=true")
        .await;
    let (_, d, _) = visit(&app, token, "", None).await;
    assert!(d["widgets"][0]["sleep_seconds"].is_null());
    assert_eq!(d["widgets"][0]["sleep_state"], "updating");
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn completed_sleep_remains_consistent_during_reanalysis() {
    let (db, app, owner, _) = setup().await;
    db.sql(r#"INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics)
      VALUES('TEST-RELIABILITY','2025-01-15T00:00:00Z','2025-01-15T08:00:00Z','main','main','UTC',false,'{"sleep":{"window":{"asleep_s":28000},"physiology":{"hrv_rmssd_ms":80,"resting_hr":50}}}');
      INSERT INTO sleep_evidence(session_id,revision,boundary_complete,hr_samples) SELECT id,revision,true,28800 FROM sleep_sessions;
      INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,generation,completed_generation) VALUES('TEST-RELIABILITY','sleep','2025-01-15','UTC',5,2,1);"#).await;
    let mut c = input(json!(["daily_rings", "sleep", "hrv", "resting_hr"]));
    c["config"]["range"] = json!("fixed");
    c["config"]["from"] = json!("2025-01-15");
    c["config"]["to"] = json!("2025-01-15");
    let (_, share, _) = req(&app, "POST", "/v1/shares", Some(&owner), None, c).await;
    let token = share["token"].as_str().unwrap();
    let (_, d, _) = visit(&app, token, "", None).await;
    assert_eq!(
        d["widgets"][1]["points"][0]["value"], d["widgets"][0]["sleep_seconds"],
        "same sleep must match"
    );
    assert_eq!(d["widgets"][0]["sleep_state"], "ready");
    assert_eq!(d["widgets"][2]["points"][0]["value"], 80);
    assert_eq!(d["widgets"][3]["points"][0]["value"], 50);
    // Without completed evidence the same queued day must remain unavailable.
    db.sql("DELETE FROM sleep_evidence").await;
    let (_, waiting, _) = visit(&app, token, "", None).await;
    assert_eq!(waiting["widgets"][0]["sleep_state"], "updating");
    for i in 1..4 {
        assert!(waiting["widgets"][i]["points"][0]["value"].is_null());
    }
    db.sql("INSERT INTO sleep_evidence(session_id,revision,boundary_complete,hr_samples) SELECT id,revision,true,28800 FROM sleep_sessions").await;
    db.sql("UPDATE sleep_sessions SET metrics_pending=true")
        .await;
    let (_, d, _) = visit(&app, token, "", None).await;
    assert!(d["widgets"][0]["sleep_seconds"].is_null());
    assert_eq!(d["widgets"][0]["sleep_state"], "updating");
    for i in 1..4 {
        assert!(d["widgets"][i]["points"][0]["value"].is_null());
    }
}
