//! End-to-end authorization tests against isolated development database schemas.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use base64::Engine;
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
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn every_device_route_enforces_ownership_and_browser_write_policy() {
    let (_db, app, owner, member) = setup().await;
    // Derive the matrix from the actual router so future endpoints cannot silently escape this test.
    let source = include_str!("../src/lib.rs");
    let routes: Vec<_> = source
        .split('"')
        .filter(|s| s.starts_with("/v1/devices/{deviceId}"))
        .collect();
    assert!(routes.len() > 20);
    for route in routes {
        let path = route
            .replace("{deviceId}", support::DEVICE)
            .replace("{date}", "2026-01-01")
            .replace("{nightOf}", "2026-01-01")
            .replace("{id}", "999");
        for method in ["GET", "POST", "PUT", "DELETE"] {
            let (status, _, _) = req(&app, method, &path, Some(&member), None, json!({})).await;
            // 405 means this HTTP method has no handler; every actual handler denies access.
            assert!(
                matches!(
                    status,
                    StatusCode::NOT_FOUND | StatusCode::FORBIDDEN | StatusCode::METHOD_NOT_ALLOWED
                ),
                "{method} {path}: {status}"
            );
            if method != "GET"
                && !(method == "PUT"
                    && (route.ends_with("/weight-goal") || route.ends_with("/profile/photo")))
            {
                let (status, _, _) = req(&app, method, &path, Some(&owner), None, json!({})).await;
                assert!(
                    matches!(
                        status,
                        StatusCode::FORBIDDEN | StatusCode::METHOD_NOT_ALLOWED
                    ),
                    "write: {method} {path}: {status}"
                );
            }
        }
    }
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/%54EST-RELIABILITY/profile",
            Some(&member),
            None,
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/OTHER/profile",
            Some(&owner),
            None,
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND,
        "admin cannot inspect other people's records"
    );
    let me = req(&app, "GET", "/v1/auth/me", Some(&member), None, json!(null))
        .await
        .1;
    assert_eq!(me["devices"], json!(["OTHER"]));
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn scoped_phone_token_preserves_reads_writes_and_ingest_contract() {
    let (db, app, owner, _) = setup().await;
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/TEST-RELIABILITY/days",
            None,
            Some("legacy-global-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/TEST-RELIABILITY/days",
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/OTHER/days",
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    let payload = json!({"device_id":"OTHER","model":"TEST","frames":[{"client_seq":1,"channel":5,"received_at":"2026-01-01T00:00:00Z","bytes":"AQID"}]});
    for route in ["/v1/ingest", "/v2/ingest"] {
        assert_eq!(
            req(
                &app,
                "POST",
                route,
                None,
                Some("owner-phone-token"),
                payload.clone()
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            req(&app, "POST", route, Some(&owner), None, payload.clone())
                .await
                .0,
            StatusCode::FORBIDDEN
        );
    }
    let own = json!({"device_id":support::DEVICE,"model":"TEST","frames":[{"client_seq":1,"channel":5,"received_at":"2026-01-01T00:00:00Z","bytes":"AQID"}]});
    let (status, receipt, _) = req(
        &app,
        "POST",
        "/v2/ingest",
        None,
        Some("owner-phone-token"),
        own,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(receipt["rejected"], 1);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 0);
    let valid = json!({"device_id":support::DEVICE,"model":"TEST","frames":[{"client_seq":2,"upload_id":"00000000-0000-4000-8000-000000000002","channel":5,"received_at":"2026-01-01T00:00:00Z","bytes":base64::engine::general_purpose::STANDARD.encode(zoop_proto::encode_frame(&[0xfe,0,0,0],1,0))}]});
    let (status, receipt, _) = req(
        &app,
        "POST",
        "/v2/ingest",
        None,
        Some("owner-phone-token"),
        valid.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(receipt["results"][0]["status"], "stored");
    assert_eq!(
        req(
            &app,
            "POST",
            "/v2/ingest",
            None,
            Some("owner-phone-token"),
            valid
        )
        .await
        .1["results"][0]["status"],
        "duplicate"
    );
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
    // Explicitly import an old installation token: only its assigned account can use it.
    db.store
        .add_account_token("owner@example.test", &digest("legacy-global-token"))
        .await
        .unwrap();
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/TEST-RELIABILITY/days",
            None,
            Some("legacy-global-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/OTHER/days",
            None,
            Some("legacy-global-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn sessions_expire_revoke_and_follow_current_roles() {
    let (db, app, owner, member) = setup().await;
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/admin/stats",
            Some(&member),
            None,
            json!(null)
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/admin/stats",
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    db.store
        .admin_snapshot(zoop_storage::AnalysisVersions {
            sleep: zoop_analytics::ALGO_VERSION,
            workout: zoop_analytics::WORKOUT_ALGO_VERSION,
        })
        .await
        .expect("operational query");
    let (status, data, _) = req(
        &app,
        "GET",
        "/v1/admin/stats",
        Some(&owner),
        None,
        json!(null),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(data["pipeline"]["accounts"], 2);
    assert_eq!(data["pipeline"]["workers"], json!([]));
    assert!(!data.to_string().contains("TEST-RELIABILITY"));
    db.sql("UPDATE accounts SET is_admin=false WHERE email='owner@example.test'")
        .await;
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/admin/stats",
            Some(&owner),
            None,
            json!(null)
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/auth/logout",
            Some(&member),
            None,
            json!(null)
        )
        .await
        .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", Some(&member), None, json!(null))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    db.sql("UPDATE web_sessions SET expires_at=now()-interval '1 second'")
        .await;
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    let owner = login(&app, "owner@example.test").await;
    let old = db
        .store
        .login_account("owner@example.test")
        .await
        .unwrap()
        .unwrap();
    db.store
        .reset_account_password(
            "owner@example.test",
            &hash_password("replacement test password").unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert!(
        !db.store
            .create_web_session(old.id, &digest("stale-session"), &old.password_hash)
            .await
            .unwrap()
    );
    db.store
        .disable_account("owner@example.test")
        .await
        .unwrap();
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/TEST-RELIABILITY/days",
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn login_origin_limits_and_session_rotation() {
    let (_db, app, owner, _) = setup().await;
    let second = login(&app, "owner@example.test").await;
    assert_ne!(owner, second);
    let r = Request::builder()
        .method("POST")
        .uri("/v1/auth/login")
        .header("origin", "https://evil.example")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"email":"owner@example.test","password":PASSWORD}).to_string(),
        ))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(r).await.unwrap().status(),
        StatusCode::FORBIDDEN
    );
    for _ in 0..10 {
        assert_eq!(
            req(
                &app,
                "POST",
                "/v1/auth/login",
                None,
                None,
                json!({"email":"missing@example.test","password":PASSWORD})
            )
            .await
            .0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/auth/login",
            None,
            None,
            json!({"email":"missing@example.test","password":PASSWORD})
        )
        .await
        .0,
        StatusCode::TOO_MANY_REQUESTS
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn private_mode_requires_provisioning() {
    let db = support::Db::new().await;
    assert!(!db.store.private_accounts_ready().await.unwrap());
    db.store
        .create_account(
            "admin@example.test",
            &hash_password(PASSWORD).unwrap(),
            true,
        )
        .await
        .unwrap();
    assert!(!db.store.private_accounts_ready().await.unwrap());
    db.store
        .bind_account_device("admin@example.test", support::DEVICE)
        .await
        .unwrap();
    assert!(db.store.private_accounts_ready().await.unwrap());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn legacy_phone_connection_probe_is_authenticated_and_data_free() {
    let (_db, app, owner, _) = setup().await;
    let path = "/v1/devices/_/latest";
    let (status, body, _) = req(
        &app,
        "GET",
        path,
        None,
        Some("owner-phone-token"),
        json!(null),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, Value::Null);
    assert_eq!(
        req(&app, "GET", path, None, Some("wrong-token"), json!(null))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        req(&app, "GET", path, Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/_/profile",
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn native_credentials_are_private_revocable_and_reset_safe() {
    let (db, app, _, _) = setup().await;
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/native/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"owner@example.test","password":PASSWORD}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()["cache-control"], "no-store");
    assert!(response.headers().get("set-cookie").is_none());
    let body: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), 10000).await.unwrap()).unwrap();
    let token = body["token"].as_str().unwrap();
    assert_eq!(token.len(), 64);
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", None, Some(token), json!({}))
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(
        req(
            &app,
            "GET",
            "/v1/devices/OTHER/profile",
            None,
            Some(token),
            json!({})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/auth/native/login",
            None,
            None,
            json!({"email":"owner@example.test","password":PASSWORD})
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        req(
            &app,
            "POST",
            "/v1/auth/native/logout",
            None,
            Some(token),
            json!({})
        )
        .await
        .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        req(&app, "GET", "/v1/auth/me", None, Some(token), json!({}))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    // Logout did not revoke the other phone. Password recovery does.
    assert!(
        db.store
            .token_account(&digest("owner-phone-token"))
            .await
            .unwrap()
            .is_some()
    );
    let old = db
        .store
        .login_account("owner@example.test")
        .await
        .unwrap()
        .unwrap();
    db.store
        .reset_account_password(
            "owner@example.test",
            &hash_password("a replacement strong password").unwrap(),
        )
        .await
        .unwrap();
    assert!(
        db.store
            .token_account(&digest("owner-phone-token"))
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        !db.store
            .create_native_token(old.id, &digest("stale-login"), &old.password_hash)
            .await
            .unwrap()
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn browser_goal_management_is_owner_scoped_and_requires_origin() {
    let (_db, app, owner, member) = setup().await;
    let path = format!("/v1/devices/{}/weight-goal", support::DEVICE);
    let body = json!({"revision":0,"active":true,"timezone":"UTC","weekly_loss_kg":0.3,"reminder_enabled":false,"reminder_weekday":1,"reminder_minute":1200});
    assert_eq!(
        req(&app, "PUT", &path, Some(&member), None, body.clone())
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    for origin in [None, Some("https://untrusted.example")] {
        let mut request = Request::builder()
            .method("PUT")
            .uri(&path)
            .header("cookie", &owner)
            .header("content-type", "application/json");
        if let Some(origin) = origin {
            request = request.header("origin", origin);
        }
        let response = app
            .clone()
            .oneshot(request.body(Body::from(body.to_string())).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::FORBIDDEN);
    }
    let (status, goal, _) = req(&app, "PUT", &path, Some(&owner), None, body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    let mut end = body;
    end["revision"] = goal["revision"].clone();
    end["active"] = json!(false);
    assert_eq!(
        req(&app, "PUT", &path, Some(&owner), None, end).await.0,
        StatusCode::OK
    );
    let detail = format!(
        "/v1/devices/{}/weight-goals/{}",
        support::DEVICE,
        goal["id"]
    );
    assert_eq!(
        req(&app, "GET", &detail, Some(&member), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", &detail, Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::OK
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn browser_photo_upload_is_owner_scoped_and_requires_origin() {
    let (db, app, owner, member) = setup().await;
    let path = format!("/v1/devices/{}/profile/photo", support::DEVICE);
    let mut jpeg = Vec::new();
    image::codecs::jpeg::JpegEncoder::new(&mut jpeg)
        .encode_image(&image::RgbImage::from_pixel(
            32,
            32,
            image::Rgb([40, 80, 120]),
        ))
        .unwrap();
    for (cookie, origin, status) in [
        (None, Some(ORIGIN), StatusCode::UNAUTHORIZED),
        (Some(owner.as_str()), None, StatusCode::FORBIDDEN),
        (
            Some(owner.as_str()),
            Some("https://untrusted.example"),
            StatusCode::FORBIDDEN,
        ),
        (Some(member.as_str()), Some(ORIGIN), StatusCode::NOT_FOUND),
        (Some(owner.as_str()), Some(ORIGIN), StatusCode::OK),
    ] {
        let mut request = Request::builder()
            .method("PUT")
            .uri(&path)
            .header("content-type", "image/jpeg");
        if let Some(cookie) = cookie {
            request = request.header("cookie", cookie);
        }
        if let Some(origin) = origin {
            request = request.header("origin", origin);
        }
        let response = app
            .clone()
            .oneshot(request.body(Body::from(jpeg.clone())).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), status);
    }
    assert_eq!(db.count("SELECT count(*) FROM profile_photos").await, 1);
    assert_eq!(
        req(&app, "GET", &path, Some(&member), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", &path, Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::OK
    );
    // The photo exception must not open other browser health writes or deletion.
    assert_eq!(
        req(&app, "DELETE", &path, Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    let profile = format!("/v1/devices/{}/profile", support::DEVICE);
    assert_eq!(
        req(&app, "PUT", &profile, Some(&owner), None, json!({}))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    // Browser uploads retain all existing validation and upload limits.
    for (bytes, status) in [
        (b"invalid".to_vec(), StatusCode::BAD_REQUEST),
        (vec![0; 262145], StatusCode::PAYLOAD_TOO_LARGE),
    ] {
        let request = Request::builder()
            .method("PUT")
            .uri(&path)
            .header("cookie", &owner)
            .header("origin", ORIGIN)
            .header("content-type", "image/jpeg")
            .body(Body::from(bytes))
            .unwrap();
        assert_eq!(app.clone().oneshot(request).await.unwrap().status(), status);
    }
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn recovery_endpoint_remains_owner_scoped_for_web_and_phone() {
    let (_db, app, owner, member) = setup().await;
    let own = "/v1/devices/TEST-RELIABILITY/days/2025-01-15/insights?tz=UTC";
    let other = "/v1/devices/OTHER/days/2025-01-15/insights?tz=UTC";
    assert_eq!(
        req(
            &app,
            "GET",
            own,
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        req(
            &app,
            "GET",
            other,
            None,
            Some("owner-phone-token"),
            json!(null)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", own, Some(&member), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        req(&app, "GET", other, Some(&owner), None, json!(null))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn admin_backlog_counts_only_current_versions_and_profile_timezones() {
    let (db, _, _, _) = setup().await;
    db.sql("INSERT INTO profiles(device_id,tz) VALUES('TEST-RELIABILITY','Europe/Athens');
        INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,generation,completed_generation,last_error) VALUES
        ('TEST-RELIABILITY','sleep','2025-01-01','Europe/Athens',5,2,1,NULL),
        ('TEST-RELIABILITY','workout','2025-01-01','Europe/Athens',5,2,1,'synthetic failure'),
        ('TEST-RELIABILITY','workout','2025-01-01','Europe/Athens',4,2,1,'retired'),
        ('TEST-RELIABILITY','sleep','2025-01-01','UTC',5,2,1,'old timezone'),
        ('OTHER','sleep','2025-01-01','UTC',5,1,1,NULL);").await;
    let stats = db
        .store
        .admin_snapshot(zoop_storage::AnalysisVersions {
            sleep: 5,
            workout: 5,
        })
        .await
        .unwrap();
    assert_eq!(stats.pending_analysis, 2);
    assert_eq!(stats.failed_analysis, 1);
    // Retired work remains available for diagnostics; no historical rows are erased.
    assert_eq!(db.count("SELECT count(*) FROM analysis_jobs").await, 5);
}
