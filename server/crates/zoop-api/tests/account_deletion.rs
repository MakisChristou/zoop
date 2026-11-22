//! Real database regressions for explicit account erasure.
#[path = "../../../tests/support/mod.rs"]
mod support;
use axum::{
    Router,
    body::Body,
    http::{Request, StatusCode},
};
use support::Db;
use tower::ServiceExt;
use zoop_api::{AppState, WebOptions, build_router};
use zoop_auth::{digest, hash_password};
use zoop_storage::{AccountDeletion, NewRawFrame};
const PASSWORD: &str = "test-only deletion password";
async fn setup() -> (Db, Router, i64, String) {
    let db = Db::new().await;
    let hash = hash_password(PASSWORD).unwrap();
    db.store
        .create_account("admin@example.test", &hash, true)
        .await
        .unwrap();
    db.store
        .create_account("member@example.test", &hash, false)
        .await
        .unwrap();
    let member = db
        .store
        .login_account("member@example.test")
        .await
        .unwrap()
        .unwrap();
    db.store
        .bind_account_device("member@example.test", support::DEVICE)
        .await
        .unwrap();
    db.store
        .add_account_token("member@example.test", &digest("member-token"))
        .await
        .unwrap();
    let app = build_router(
        AppState::new(db.store.clone(), "legacy".into()).with_web(WebOptions {
            origin: "https://zoop.example".into(),
            secure_cookie: true,
        }),
    );
    (db, app, member.id, hash)
}
async fn delete(app: &Router, password: &str, origin: Option<&str>, token: &str) -> StatusCode {
    let mut r = Request::builder()
        .method("DELETE")
        .uri("/v1/account")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"));
    if let Some(origin) = origin {
        r = r.header("origin", origin);
    }
    app.clone()
        .oneshot(
            r.body(Body::from(
                serde_json::json!({"password":password}).to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap()
        .status()
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn deletion_requires_password_rejects_browser_bearer_and_revokes_owned_data() {
    let (db, app, id, _) = setup().await;
    let raw = db.raw(1).await;
    db.store
        .upsert_sample(&support::sample(raw, chrono::Utc::now()))
        .await
        .unwrap();
    db.sql("INSERT INTO profiles(device_id) VALUES ('TEST-RELIABILITY'); INSERT INTO devices(id,model) VALUES('OTHER','TEST'); INSERT INTO profiles(device_id) VALUES ('OTHER')").await;
    assert_eq!(
        delete(&app, PASSWORD, None, "wrong").await,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        delete(&app, "incorrect", None, "member-token").await,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        delete(&app, PASSWORD, Some("https://zoop.example"), "member-token").await,
        StatusCode::FORBIDDEN
    );
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
    assert_eq!(
        delete(&app, PASSWORD, None, "member-token").await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 0);
    assert_eq!(
        db.count("SELECT count(*) FROM profiles WHERE device_id='OTHER'")
            .await,
        1
    );
    assert_eq!(
        db.count("SELECT count(*) FROM devices WHERE id='TEST-RELIABILITY'")
            .await,
        0
    );
    assert_eq!(
        delete(&app, PASSWORD, None, "member-token").await,
        StatusCode::UNAUTHORIZED
    );
    assert!(
        db.store
            .upsert_owned_device(id, support::DEVICE, "TEST", None)
            .await
            .is_err()
    );
    // A serial reassigned to someone else cannot accept an old account's in-flight batch.
    db.store
        .bind_account_device("admin@example.test", support::DEVICE)
        .await
        .unwrap();
    db.store
        .upsert_device(support::DEVICE, "TEST", None)
        .await
        .unwrap();
    let frame = NewRawFrame {
        device_id: support::DEVICE,
        client_seq: 2,
        upload_id: None,
        channel: 5,
        received_at: chrono::Utc::now(),
        bytes: &[1, 2, 3],
    };
    assert!(db.store.insert_owned_raw_frame(&frame, id).await.is_err());
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 0);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn last_administrator_and_changed_password_are_protected() {
    let (db, _, id, hash) = setup().await;
    let admin = db
        .store
        .login_account("admin@example.test")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        db.store.delete_account(admin.id, &hash).await.unwrap(),
        AccountDeletion::LastAdministrator
    );
    assert_eq!(
        db.store.delete_account(id, "stale-hash").await.unwrap(),
        AccountDeletion::CredentialsChanged
    );
    assert_eq!(db.count("SELECT count(*) FROM accounts").await, 2);
    db.store
        .create_account("second@example.test", &hash, true)
        .await
        .unwrap();
    let second = db
        .store
        .login_account("second@example.test")
        .await
        .unwrap()
        .unwrap();
    let (a, b) = tokio::join!(
        db.store.delete_account(admin.id, &hash),
        db.store.delete_account(second.id, &hash)
    );
    let results = [a.unwrap(), b.unwrap()];
    assert!(results.contains(&AccountDeletion::Deleted));
    assert!(results.contains(&AccountDeletion::LastAdministrator));
    assert_eq!(
        db.count("SELECT count(*) FROM accounts WHERE enabled AND is_admin")
            .await,
        1
    );
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn erasure_waits_for_in_flight_owner_transaction_then_removes_it() {
    let (db, _, id, hash) = setup().await;
    let mut tx = db.pool.begin().await.unwrap();
    sqlx::query("SELECT id FROM accounts WHERE id=$1 FOR SHARE")
        .bind(id)
        .execute(&mut *tx)
        .await
        .unwrap();
    db.raw(1).await;
    let store = db.store.clone();
    let deletion = tokio::spawn(async move { store.delete_account(id, &hash).await });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(!deletion.is_finished());
    tx.commit().await.unwrap();
    assert_eq!(deletion.await.unwrap().unwrap(), AccountDeletion::Deleted);
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn every_device_table_is_included_in_erasure_policy() {
    let (db, _, _, _) = setup().await;
    let tables: Vec<String> = sqlx::query_scalar("SELECT table_name FROM information_schema.columns WHERE table_schema=current_schema() AND column_name='device_id' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema=current_schema() AND table_type='BASE TABLE')")
        .fetch_all(&db.pool).await.unwrap();
    let source = include_str!("../../zoop-storage/src/account_deletion.rs");
    for table in tables {
        assert!(
            source.contains(&table),
            "Account deletion must handle new table {table}"
        );
    }
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn account_deletion_erases_saved_dashboard_layout() {
    let (db, _app, id, hash) = setup().await;
    db.store.upsert_device("OTHER", "TEST", None).await.unwrap();
    db.store
        .bind_account_device("admin@example.test", "OTHER")
        .await
        .unwrap();
    db.sql("INSERT INTO dashboard_layouts(account_id,device_id,config) SELECT account_id,device_id,'{}'::jsonb FROM device_owners").await;
    assert_eq!(db.count("SELECT count(*) FROM dashboard_layouts").await, 2);
    assert_eq!(
        db.store.delete_account(id, &hash).await.unwrap(),
        AccountDeletion::Deleted
    );
    assert_eq!(db.count("SELECT count(*) FROM dashboard_layouts").await, 1);
    assert_eq!(
        db.count("SELECT count(*) FROM dashboard_layouts WHERE device_id='OTHER'")
            .await,
        1
    );
}
