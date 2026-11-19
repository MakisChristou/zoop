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
async fn every_device_route_enforces_ownership_and_browser_read_only() {
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
            if method != "GET" {
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
    db.store.admin_snapshot().await.expect("operational query");
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
