//! First-run setup, concurrency and installation ownership boundaries.
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
const ORIGIN: &str = "http://192.168.1.10:8080";
const CODE: &str = "synthetic-setup-code-for-tests-only-32";
fn app(db: &Db, setup: bool) -> Router {
    let state = AppState::new(db.store.clone(), "legacy-test-token".into()).with_web(WebOptions {
        origin: ORIGIN.into(),
        secure_cookie: false,
    });
    build_router(if setup {
        state.with_setup_token(CODE.into())
    } else {
        state
    })
}
async fn request(
    app: &Router,
    method: &str,
    path: &str,
    origin: &str,
    input: Value,
) -> (StatusCode, Value) {
    let r = app
        .clone()
        .oneshot(
            Request::builder()
                .method(method)
                .uri(path)
                .header("origin", origin)
                .header("content-type", "application/json")
                .body(Body::from(input.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = r.status();
    let bytes = to_bytes(r.into_body(), 10000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
fn input() -> Value {
    json!({"code":CODE,"email":"owner@example.test","password":"synthetic owner password","device":"TEST-OWNER"})
}
async fn empty_db() -> Db {
    let db = Db::new().await;
    db.sql("DELETE FROM devices").await;
    db
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn setup_requires_code_origin_and_empty_installation_and_stays_closed_after_restart() {
    let db = empty_db().await;
    let router = app(&db, true);
    assert_eq!(
        request(&router, "GET", "/v1/setup", ORIGIN, Value::Null)
            .await
            .1["available"],
        true
    );
    assert_eq!(
        request(
            &router,
            "POST",
            "/v1/setup",
            "http://attacker.test",
            input()
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let mut wrong = input();
    wrong["code"] = json!("wrong");
    assert_eq!(
        request(&router, "POST", "/v1/setup", ORIGIN, wrong).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(db.count("SELECT count(*) FROM accounts").await, 0);
    assert_eq!(
        request(&router, "GET", "/v1/admin/stats", ORIGIN, Value::Null)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        request(&router, "POST", "/v1/setup", ORIGIN, input())
            .await
            .0,
        StatusCode::CREATED
    );
    let owner = db
        .store
        .login_account("owner@example.test")
        .await
        .unwrap()
        .unwrap();
    assert!(owner.is_admin);
    assert!(zoop_auth::verify_password(
        "synthetic owner password",
        &owner.password_hash
    ));
    assert!(db.store.owns_device(owner.id, "TEST-OWNER").await.unwrap());
    assert!(!db.store.owns_device(owner.id, "OTHER").await.unwrap());
    assert_eq!(
        db.store.pending_account_devices(owner.id).await.unwrap(),
        ["TEST-OWNER"]
    );
    // Another user's reservation stays private; an actual upload clears waiting.
    assert!(
        db.store
            .pending_account_devices(owner.id + 1)
            .await
            .unwrap()
            .is_empty()
    );
    db.store
        .upsert_device("TEST-OWNER", "TEST", None)
        .await
        .unwrap();
    assert!(
        db.store
            .pending_account_devices(owner.id)
            .await
            .unwrap()
            .is_empty()
    );
    let restarted = app(&db, true);
    assert_eq!(
        request(&restarted, "GET", "/v1/setup", ORIGIN, Value::Null)
            .await
            .1["available"],
        false
    );
    assert_eq!(
        request(&restarted, "POST", "/v1/setup", ORIGIN, input())
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    db.store
        .disable_account("owner@example.test")
        .await
        .unwrap();
    assert!(!db.store.setup_available().await.unwrap());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn concurrent_setup_creates_exactly_one_admin() {
    let db = empty_db().await;
    let router = app(&db, true);
    let a = request(&router, "POST", "/v1/setup", ORIGIN, input());
    let b = request(&router, "POST", "/v1/setup", ORIGIN, input());
    let (a, b) = tokio::join!(a, b);
    assert_eq!(
        [a.0, b.0]
            .iter()
            .filter(|s| **s == StatusCode::CREATED)
            .count(),
        1
    );
    assert_eq!(db.count("SELECT count(*) FROM accounts").await, 1);
    assert_eq!(db.count("SELECT count(*) FROM device_owners").await, 1);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn setup_never_claims_existing_data_or_activates_without_operator_code() {
    let db = Db::new().await;
    assert!(!db.store.setup_available().await.unwrap());
    assert_eq!(
        request(&app(&db, true), "POST", "/v1/setup", ORIGIN, input())
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    let empty = empty_db().await;
    assert_eq!(
        request(&app(&empty, false), "GET", "/v1/setup", ORIGIN, Value::Null)
            .await
            .1["available"],
        false
    );
    assert_eq!(
        request(&app(&empty, false), "POST", "/v1/setup", ORIGIN, input())
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    let mut bad = input();
    bad["device"] = json!("bad/serial");
    assert_eq!(
        request(&app(&empty, true), "POST", "/v1/setup", ORIGIN, bad)
            .await
            .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(empty.count("SELECT count(*) FROM accounts").await, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn setup_limits_guesses_and_request_size() {
    let db = empty_db().await;
    let router = app(&db, true);
    let mut bad = input();
    bad["code"] = json!("wrong");
    for _ in 0..10 {
        assert_eq!(
            request(&router, "POST", "/v1/setup", ORIGIN, bad.clone())
                .await
                .0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(
        request(&router, "POST", "/v1/setup", ORIGIN, input())
            .await
            .0,
        StatusCode::TOO_MANY_REQUESTS
    );
    let mut huge = input();
    huge["code"] = json!("x".repeat(5000));
    assert_eq!(
        request(&router, "POST", "/v1/setup", ORIGIN, huge).await.0,
        StatusCode::PAYLOAD_TOO_LARGE
    );
}
