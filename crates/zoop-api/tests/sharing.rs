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
