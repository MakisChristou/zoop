//! Full-router tests: separate principals, consent, MCP and OAuth replay protection.
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
use zoop_auth::digest;
const ORIGIN: &str = "https://zoop.example";
const DEVICE: &str = support::DEVICE;
struct Fixture {
    db: Db,
    app: Router,
    owner: String,
    member: String,
    owner_id: i64,
}
impl Fixture {
    async fn new() -> Self {
        let db = Db::new().await;
        let a = db
            .store
            .create_account("owner@example.test", "test-password-hash", true)
            .await
            .unwrap();
        let b = db
            .store
            .create_account("member@example.test", "other-hash", false)
            .await
            .unwrap();
        db.store
            .bind_account_device(&a.email, DEVICE)
            .await
            .unwrap();
        db.store.upsert_device("OTHER", "TEST", None).await.unwrap();
        db.store
            .bind_account_device(&b.email, "OTHER")
            .await
            .unwrap();
        let owner = "a".repeat(64);
        let member = "b".repeat(64);
        db.store
            .create_web_session(a.id, &digest(&owner), "test-password-hash")
            .await
            .unwrap();
        db.store
            .create_web_session(b.id, &digest(&member), "other-hash")
            .await
            .unwrap();
        db.store
            .add_account_token(&a.email, &digest("phone-token"))
            .await
            .unwrap();
        let app = build_router(
            AppState::new(db.store.clone(), "global-token".into()).with_web(WebOptions {
                origin: ORIGIN.into(),
                secure_cookie: true,
            }),
        );
        Self {
            db,
            app,
            owner: format!("zoop_session={owner}"),
            member: format!("zoop_session={member}"),
            owner_id: a.id,
        }
    }
    async fn key(&self, scopes: Value, history: Value) -> (String, i64) {
        let (status,v)=req(&self.app,"POST","/v1/agent-connections",Some(&self.owner),None,Some(ORIGIN),json!({"device_id":DEVICE,"name":"Test assistant","scopes":scopes,"history_days":history,"timezone":"UTC","expires_in_days":90})).await;
        assert_eq!(status, StatusCode::OK, "{v}");
        (
            v["key"].as_str().unwrap().into(),
            v["connection"]["id"].as_i64().unwrap(),
        )
    }
}
async fn req(
    app: &Router,
    method: &str,
    path: &str,
    cookie: Option<&str>,
    bearer: Option<&str>,
    origin: Option<&str>,
    body: Value,
) -> (StatusCode, Value) {
    let mut b = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json")
        .header("host", "zoop.example")
        .header("accept", "application/json, text/event-stream");
    if let Some(c) = cookie {
        b = b.header("cookie", c)
    }
    if let Some(t) = bearer {
        b = b.header("authorization", format!("Bearer {t}"))
    }
    if let Some(o) = origin {
        b = b.header("origin", o)
    }
    let r = app
        .clone()
        .oneshot(b.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = r.status();
    let bytes = to_bytes(r.into_body(), 2_000_000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes)
            .unwrap_or_else(|_| json!({"body":String::from_utf8_lossy(&bytes)})),
    )
}
fn consent(device: &str) -> Value {
    json!({"device_id":device,"name":"Assistant","scopes":["sleep:read"],"history_days":30,"timezone":"UTC","expires_in_days":90})
}
#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn credentials_cannot_cross_accounts_or_authentication_surfaces() {
    let f = Fixture::new().await;
    let (key, id) = f.key(json!(["weight:read"]), json!(30)).await;
    let (_, rows) = req(
        &f.app,
        "GET",
        "/v1/agent-connections",
        Some(&f.member),
        None,
        None,
        Value::Null,
    )
    .await;
    assert_eq!(rows["connections"], json!([]));
    assert_eq!(
        req(
            &f.app,
            "DELETE",
            &format!("/v1/agent-connections/{id}"),
            Some(&f.member),
            None,
            Some(ORIGIN),
            Value::Null
        )
        .await
        .0,
        404
    );
    // Being an administrator does not allow binding another user's device.
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent-connections",
            Some(&f.owner),
            None,
            Some(ORIGIN),
            consent("OTHER")
        )
        .await
        .0,
        403
    );
    for (method, path) in [
        ("GET", "/v1/auth/me"),
        ("GET", "/v1/admin/stats"),
        ("GET", "/v1/devices/TEST-RELIABILITY/weights"),
        ("PUT", "/v1/devices/TEST-RELIABILITY/weight-goal"),
        ("POST", "/v1/ingest"),
        ("POST", "/v2/ingest"),
        ("DELETE", "/v1/account"),
        ("POST", "/v1/shares"),
        ("POST", "/v1/agent-connections"),
    ] {
        assert!(
            matches!(
                req(
                    &f.app,
                    method,
                    path,
                    None,
                    Some(&key),
                    Some(ORIGIN),
                    json!({})
                )
                .await
                .0
                .as_u16(),
                401 | 403
            ),
            "{method} {path}"
        );
    }
    for bearer in ["phone-token", "global-token", "invalid"] {
        assert_eq!(
            req(
                &f.app,
                "GET",
                "/v1/agent/available_data",
                None,
                Some(bearer),
                None,
                Value::Null
            )
            .await
            .0,
            401
        );
    }
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            Some(&f.owner),
            None,
            None,
            Value::Null
        )
        .await
        .0,
        403
    );
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            Some("https://evil.example"),
            Value::Null
        )
        .await
        .0,
        403
    );
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent-connections",
            Some(&f.owner),
            None,
            None,
            consent(DEVICE)
        )
        .await
        .0,
        403
    );
    let (_, list) = req(
        &f.app,
        "GET",
        "/v1/agent-connections",
        Some(&f.owner),
        None,
        None,
        Value::Null,
    )
    .await;
    assert!(!list.to_string().contains(&key));
    assert!(!list.to_string().contains(DEVICE));
    assert_eq!(
        f.db.count("SELECT count(*) FROM agent_credentials WHERE digest LIKE 'zoop_%'")
            .await,
        0
    );
    assert_eq!(
        f.db.count(&format!(
            "SELECT count(*) FROM agent_connections WHERE account_id={}",
            f.owner_id
        ))
        .await,
        1
    );
}
#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn scope_and_date_limits_cover_nested_data_and_forged_parameters() {
    let f = Fixture::new().await;
    let (key, _) = f.key(json!(["activity:read"]), json!(30)).await;
    let (status, v) = req(
        &f.app,
        "GET",
        "/v1/agent/daily_summary",
        None,
        Some(&key),
        None,
        Value::Null,
    )
    .await;
    assert_eq!(status, 200, "{v}");
    assert!(v["data"]["steps"].is_array());
    for k in [
        "sleep_seconds",
        "recovery",
        "weight_kg",
        "hrv_ms",
        "resting_hr",
    ] {
        assert!(v["data"].get(k).is_none(), "{k}");
    }
    for tool in [
        "sleep_history",
        "recovery_history",
        "weight_history",
        "goals",
    ] {
        assert_eq!(
            req(
                &f.app,
                "GET",
                &format!("/v1/agent/{tool}"),
                None,
                Some(&key),
                None,
                Value::Null
            )
            .await
            .0,
            403
        );
    }
    for query in [
        "?account_id=2",
        "?device_id=OTHER",
        "?tz=UTC",
        "?from=2000-01-01&to=2000-01-02",
        "?from=2026-01-01&to=2026-12-31",
        "?from=2099-01-01",
        "?to=-262143-01-01",
    ] {
        assert_eq!(
            req(
                &f.app,
                "GET",
                &format!("/v1/agent/daily_summary{query}"),
                None,
                Some(&key),
                None,
                Value::Null
            )
            .await
            .0,
            400,
            "{query}"
        );
    }
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent/daily_summary",
            None,
            Some(&key),
            None,
            json!({})
        )
        .await
        .0,
        405
    );
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/sql",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        404
    );
}
#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn key_revocation_expiry_password_and_device_changes_are_immediate() {
    let f = Fixture::new().await;
    let (key, id) = f.key(json!(["sleep:read"]), json!(30)).await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        200
    );
    req(
        &f.app,
        "DELETE",
        &format!("/v1/agent-connections/{id}"),
        Some(&f.owner),
        None,
        Some(ORIGIN),
        Value::Null,
    )
    .await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    let (key, id) = f.key(json!(["sleep:read"]), json!(30)).await;
    f.db.sql(&format!(
        "UPDATE agent_connections SET expires_at=now()-interval '1 second' WHERE id={id}"
    ))
    .await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    let (key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    f.db.sql("UPDATE accounts SET password_hash='new-hash' WHERE email='owner@example.test'")
        .await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    let (key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    f.db.sql("UPDATE device_owners SET account_id=(SELECT id FROM accounts WHERE email='member@example.test') WHERE device_id='TEST-RELIABILITY'").await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    // Moving it back cannot revive the grant.
    f.db.sql("UPDATE device_owners SET account_id=(SELECT id FROM accounts WHERE email='owner@example.test') WHERE device_id='TEST-RELIABILITY'").await;
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    let (key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    f.db.store
        .disable_account("owner@example.test")
        .await
        .unwrap();
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
}
// RFC 7636 published test vector. It is not a production secret.
const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const CHALLENGE: &str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
async fn authorization(f: &Fixture) -> (String, Value) {
    let (status,client)=req(&f.app,"POST","/oauth/register",None,None,None,json!({"client_name":"Test public client","redirect_uris":["http://127.0.0.1:9000/callback"],"token_endpoint_auth_method":"none"})).await;
    assert_eq!(status, 201, "{client}");
    let id = client["client_id"].as_str().unwrap().to_string();
    let a = json!({"client_id":id,"redirect_uri":"http://127.0.0.1:9000/callback","response_type":"code","code_challenge":CHALLENGE,"code_challenge_method":"S256","resource":format!("{ORIGIN}/mcp"),"scope":"sleep:read","state":"client-state"});
    (id, a)
}
async fn approve(f: &Fixture, a: Value) -> String {
    let (status, v) = req(
        &f.app,
        "POST",
        "/v1/agent-authorization",
        Some(&f.owner),
        None,
        Some(ORIGIN),
        json!({"authorization":a,"consent":consent(DEVICE)}),
    )
    .await;
    assert_eq!(status, 200, "{v}");
    let url = v["redirect_to"].as_str().unwrap();
    assert!(url.contains("state=client-state"));
    assert!(url.contains("iss=https%3A%2F%2Fzoop.example"));
    url.split("code=")
        .nth(1)
        .unwrap()
        .split('&')
        .next()
        .unwrap()
        .into()
}
async fn exchange(f: &Fixture, fields: &[(&str, &str)]) -> (StatusCode, Value) {
    // Values used in these tests are all unreserved except the resource/callback URL.
    let body = fields
        .iter()
        .map(|(k, v)| format!("{k}={}", v.replace(':', "%3A").replace('/', "%2F")))
        .collect::<Vec<_>>()
        .join("&");
    let response = f
        .app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/oauth/token")
                .header("content-type", "application/x-www-form-urlencoded")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 100000).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}
#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn oauth_requires_consent_pkce_client_redirect_resource_and_rotates_refreshes() {
    let f = Fixture::new().await;
    let (client, auth) = authorization(&f).await;
    for (field, value) in [
        ("redirect_uri", "https://evil.example/cb"),
        ("resource", "https://evil.example/mcp"),
        ("code_challenge_method", "plain"),
    ] {
        let mut bad = auth.clone();
        bad[field] = json!(value);
        assert_eq!(
            req(
                &f.app,
                "POST",
                "/v1/agent-authorization",
                Some(&f.owner),
                None,
                Some(ORIGIN),
                json!({"authorization":bad,"consent":consent(DEVICE)})
            )
            .await
            .0,
            400
        );
    }
    let mut wide = consent(DEVICE);
    wide["scopes"] = json!(["weight:read"]);
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent-authorization",
            Some(&f.owner),
            None,
            Some(ORIGIN),
            json!({"authorization":auth,"consent":wide})
        )
        .await
        .0,
        403
    );
    let code = approve(&f, auth).await;
    let base = [
        ("grant_type", "authorization_code"),
        ("client_id", client.as_str()),
        ("code", code.as_str()),
        ("redirect_uri", "http://127.0.0.1:9000/callback"),
        ("code_verifier", VERIFIER),
        ("resource", "https://zoop.example/mcp"),
    ];
    for (index, value) in [
        (1, "other-client"),
        (3, "https://evil.example/callback"),
        (4, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        (5, "https://evil.example/mcp"),
    ] {
        let mut bad = base;
        bad[index].1 = value;
        assert_eq!(exchange(&f, &bad).await.0, 400);
    }
    let (status, t) = exchange(&f, &base).await;
    assert_eq!(status, 200, "{t}");
    let access = t["access_token"].as_str().unwrap();
    let refresh = t["refresh_token"].as_str().unwrap();
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(access),
            None,
            Value::Null
        )
        .await
        .0,
        200
    );
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/weight_history",
            None,
            Some(access),
            None,
            Value::Null
        )
        .await
        .0,
        403
    );
    let refresh_request = [
        ("grant_type", "refresh_token"),
        ("client_id", client.as_str()),
        ("refresh_token", refresh),
        ("resource", "https://zoop.example/mcp"),
    ];
    let (status, new) = exchange(&f, &refresh_request).await;
    assert_eq!(status, 200, "{new}");
    assert_ne!(new["refresh_token"], t["refresh_token"]);
    assert_eq!(exchange(&f, &refresh_request).await.0, 400);
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(new["access_token"].as_str().unwrap()),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
}
#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn mcp_authenticates_each_request_and_exposes_only_permitted_tools() {
    let f = Fixture::new().await;
    let (key, id) = f.key(json!(["sleep:read"]), json!(30)).await;
    let initialize = json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}});
    assert_eq!(
        req(&f.app, "POST", "/mcp", None, None, None, initialize.clone())
            .await
            .0,
        401
    );
    let (status, v) = req(&f.app, "POST", "/mcp", None, Some(&key), None, initialize).await;
    assert_eq!(status, 200, "{v}");
    assert!(v["result"]["capabilities"]["tools"].is_object(), "{v}");
    let list = json!({"jsonrpc":"2.0","id":2,"method":"tools/list"});
    let (status, v) = req(&f.app, "POST", "/mcp", None, Some(&key), None, list.clone()).await;
    assert_eq!(status, 200, "{v}");
    let names = v["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v["name"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert!(names.contains(&"sleep_history"));
    assert!(!names.contains(&"weight_history"));
    let call = json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"weight_history","arguments":{}}});
    let (_, v) = req(&f.app, "POST", "/mcp", None, Some(&key), None, call).await;
    assert_eq!(v["result"]["isError"], true, "{v}");
    f.db.store
        .revoke_agent_connection(f.owner_id, id)
        .await
        .unwrap();
    assert_eq!(
        req(&f.app, "POST", "/mcp", None, Some(&key), None, list)
            .await
            .0,
        401
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn actual_readings_remain_isolated_and_match_backend_projection() {
    let f = Fixture::new().await;
    f.db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','private-id',now()-interval '1 hour',60,'health','private source'),('OTHER','other-private-id',now()-interval '1 hour',90,'snoop','other source'),('TEST-RELIABILITY','removed',now()-interval '2 hours',65,'snoop','private source'); UPDATE weight_readings SET removed=true WHERE id='removed'").await;
    let (owner_key, _) = f.key(json!(["weight:read"]), json!(30)).await;
    let mut c = consent("OTHER");
    c["scopes"] = json!(["weight:read"]);
    let (status, member) = req(
        &f.app,
        "POST",
        "/v1/agent-connections",
        Some(&f.member),
        None,
        Some(ORIGIN),
        c,
    )
    .await;
    assert_eq!(status, 200);
    for (key, kg) in [
        (owner_key.as_str(), 60),
        (member["key"].as_str().unwrap(), 90),
    ] {
        let (status, v) = req(
            &f.app,
            "GET",
            "/v1/agent/weight_history",
            None,
            Some(key),
            None,
            Value::Null,
        )
        .await;
        assert_eq!(status, 200, "{v}");
        let readings = v["data"]["readings"].as_array().unwrap();
        assert_eq!(readings.len(), 1);
        assert_eq!(readings[0]["kg"].as_f64().unwrap(), f64::from(kg));
        for secret in [
            "private-id",
            "other-private-id",
            "private source",
            "other source",
            "TEST-RELIABILITY",
            "OTHER",
            "@example",
        ] {
            assert!(!v.to_string().contains(secret), "{secret}");
        }
    }
    let (_, summary) = req(
        &f.app,
        "GET",
        "/v1/agent/daily_summary",
        None,
        Some(&owner_key),
        None,
        Value::Null,
    )
    .await;
    let from = summary["from"].as_str().unwrap().parse().unwrap();
    let to = summary["to"].as_str().unwrap().parse().unwrap();
    let expected =
        f.db.store
            .shared_points(
                DEVICE,
                "UTC",
                from,
                to,
                "weight",
                zoop_analytics::ALGO_VERSION,
            )
            .await
            .unwrap();
    assert_eq!(summary["data"]["weight_kg"], json!(expected));
    let call = json!({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"daily_summary","arguments":{}}});
    let (status, mcp) = req(&f.app, "POST", "/mcp", None, Some(&owner_key), None, call).await;
    assert_eq!(status, 200, "{mcp}");
    assert_eq!(mcp["result"]["structuredContent"]["data"], summary["data"]);
    // Even without providing a device parameter, changing the bearer changes the data owner.
    let count = f.db.count("SELECT count(*) FROM weight_readings").await;
    assert_eq!(count, 3);
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn sleep_projection_keeps_corrections_pending_and_physiology_scope_separate() {
    let f = Fixture::new().await;
    f.db.sql(r#"INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,edited,fixed,timezone,metrics)
      VALUES('TEST-RELIABILITY',now()-interval '10 hours',now()-interval '2 hours','main','main',true,true,'UTC',
      '{"sleep":{"window":{"asleep_s":27000,"efficiency":94},"stages":{"deep_s":5000},"physiology":{"hrv_rmssd_ms":55,"resting_hr":48}}}');
      INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,metrics_pending) VALUES('TEST-RELIABILITY',now()-interval '90 minutes',now()-interval '60 minutes','nap','nap',true);
      INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,status) VALUES('TEST-RELIABILITY',now()-interval '12 hours',now()-interval '11 hours','nap','nap','removed');"#).await;
    let (key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    let (status, v) = req(
        &f.app,
        "GET",
        "/v1/agent/sleep_history",
        None,
        Some(&key),
        None,
        Value::Null,
    )
    .await;
    assert_eq!(status, 200, "{v}");
    let rows = v["data"]["sessions"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0]["edited"], true);
    assert_eq!(rows[0]["metrics"]["window"]["asleep_s"], 27000);
    assert_eq!(rows[1]["pending"], true);
    assert_eq!(rows[1]["metrics"], Value::Null);
    assert!(!v.to_string().contains("hrv"));
    assert!(!v.to_string().contains("resting_hr"));
    let (all_key, _) = f.key(json!(["recovery:read"]), Value::Null).await;
    let (status, actual) = req(
        &f.app,
        "GET",
        "/v1/agent/recovery_history",
        None,
        Some(&all_key),
        None,
        Value::Null,
    )
    .await;
    assert_eq!(status, 200, "{actual}");
    let expected = zoop_core::daily_recovery_history(
        &f.db.store,
        DEVICE,
        actual["from"].as_str().unwrap().parse().unwrap(),
        actual["to"].as_str().unwrap().parse().unwrap(),
        "UTC",
    )
    .await
    .unwrap();
    let expected = expected.unwrap();
    let actual_days = actual["data"]["days"].as_array().unwrap();
    assert_eq!(actual_days.len(), expected.len());
    for (actual, expected) in actual_days.iter().zip(expected) {
        assert_eq!(actual["day"], json!(expected.day));
        assert_eq!(actual["recovery"]["score"], json!(expected.recovery.score));
        assert_eq!(actual["recovery"]["state"], json!(expected.recovery.state));
        assert_eq!(actual["recovery"]["band"], json!(expected.recovery.band));
        assert_eq!(actual["hrv_ms"], json!(expected.hrv_ms));
        assert_eq!(actual["resting_hr"], json!(expected.resting_hr));
        let fields = actual["recovery"].as_object().unwrap();
        assert_eq!(fields.len(), 5);
        assert!(!fields.contains_key("components"));
        assert!(!fields.contains_key("baseline_count"));
    }
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn timezone_boundaries_and_filtered_steps_are_canonical() {
    let f = Fixture::new().await;
    let today =
        f.db.store
            .weight_local_day(chrono::Utc::now(), "America/New_York")
            .await
            .unwrap();
    let start = today - chrono::Duration::days(5);
    let timestamp = format!("{start}T04:30:00Z"); // Standard time: preceding local day.
    f.db.sql(&format!("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','boundary','{timestamp}',60,'snoop','test')")).await;
    let mut c = consent(DEVICE);
    c["scopes"] = json!(["weight:read", "activity:read"]);
    c["timezone"] = json!("America/New_York");
    let (status, key) = req(
        &f.app,
        "POST",
        "/v1/agent-connections",
        Some(&f.owner),
        None,
        Some(ORIGIN),
        c,
    )
    .await;
    assert_eq!(status, 200);
    let key = key["key"].as_str().unwrap();
    let (_, v) = req(
        &f.app,
        "GET",
        "/v1/agent/weight_history",
        None,
        Some(key),
        None,
        Value::Null,
    )
    .await;
    let expected_day =
        f.db.store
            .weight_local_day(timestamp.parse().unwrap(), "America/New_York")
            .await
            .unwrap();
    assert_eq!(v["data"]["readings"][0]["day"], json!(expected_day));
    // A canonical cache fixture deliberately distinguishes filtered and raw steps.
    f.db.sql(&format!("INSERT INTO day_summary_cache(device_id,tz,day,start_ts,end_ts,dirty,steps,steps_walking,samples) VALUES('TEST-RELIABILITY','America/New_York','{start}','{start}'::date::timestamp AT TIME ZONE 'America/New_York',('{start}'::date+1)::timestamp AT TIME ZONE 'America/New_York',false,9000,1200,100)")).await;
    let (_, v) = req(
        &f.app,
        "GET",
        "/v1/agent/daily_summary",
        None,
        Some(key),
        None,
        Value::Null,
    )
    .await;
    let expected =
        f.db.store
            .shared_points(
                DEVICE,
                "America/New_York",
                v["from"].as_str().unwrap().parse().unwrap(),
                v["to"].as_str().unwrap().parse().unwrap(),
                "steps",
                zoop_analytics::ALGO_VERSION,
            )
            .await
            .unwrap();
    assert_eq!(v["data"]["steps"], json!(expected));
    assert!(
        v["data"]["steps"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v["value"] == 1200)
    );
    assert!(
        !v["data"]["steps"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v["value"] == 9000)
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn codes_expire_are_single_use_and_connections_survive_router_restart() {
    let f = Fixture::new().await;
    let (client, auth) = authorization(&f).await;
    let code = approve(&f, auth.clone()).await;
    f.db.sql("UPDATE agent_credentials SET expires_at=now()-interval '1 second' WHERE kind='code'")
        .await;
    let request = |code| {
        [
            ("grant_type", "authorization_code"),
            ("client_id", client.as_str()),
            ("code", code),
            ("redirect_uri", "http://127.0.0.1:9000/callback"),
            ("code_verifier", VERIFIER),
            ("resource", "https://zoop.example/mcp"),
        ]
    };
    assert_eq!(exchange(&f, &request(&code)).await.0, 400);
    let code = approve(&f, auth).await;
    let (status, token) = exchange(&f, &request(&code)).await;
    assert_eq!(status, 200);
    assert_eq!(exchange(&f, &request(&code)).await.0, 400);
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(token["access_token"].as_str().unwrap()),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
    let (key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    let restarted = build_router(
        AppState::new(f.db.store.clone(), "global-token".into()).with_web(WebOptions {
            origin: ORIGIN.into(),
            secure_cookie: true,
        }),
    );
    assert_eq!(
        req(
            &restarted,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        200
    );
    let legacy = build_router(AppState::new(f.db.store.clone(), "global-token".into()));
    assert_eq!(
        req(
            &legacy,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&key),
            None,
            Value::Null
        )
        .await
        .0,
        404
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn account_erasure_removes_agent_secrets_and_preserves_other_accounts() {
    let f = Fixture::new().await;
    let (owner_key, _) = f.key(json!(["sleep:read"]), json!(30)).await;
    let (status, member) = req(
        &f.app,
        "POST",
        "/v1/agent-connections",
        Some(&f.member),
        None,
        Some(ORIGIN),
        consent("OTHER"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let member_id =
        f.db.store
            .login_account("member@example.test")
            .await
            .unwrap()
            .unwrap()
            .id;
    assert_eq!(
        f.db.store
            .delete_account(member_id, "other-hash")
            .await
            .unwrap(),
        zoop_storage::AccountDeletion::Deleted
    );
    assert_eq!(
        f.db.count("SELECT count(*) FROM agent_connections").await,
        1
    );
    assert_eq!(
        f.db.count("SELECT count(*) FROM agent_credentials").await,
        1
    );
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            member["key"].as_str(),
            None,
            Value::Null
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            Some(&owner_key),
            None,
            Value::Null
        )
        .await
        .0,
        StatusCode::OK
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn simultaneous_code_exchange_has_one_winner_and_revokes_on_reuse() {
    let f = Fixture::new().await;
    let (client, auth) = authorization(&f).await;
    let code = approve(&f, auth).await;
    let fields = [
        ("grant_type", "authorization_code"),
        ("client_id", client.as_str()),
        ("code", code.as_str()),
        ("redirect_uri", "http://127.0.0.1:9000/callback"),
        ("code_verifier", VERIFIER),
        ("resource", "https://zoop.example/mcp"),
    ];
    let (a, b) = tokio::join!(exchange(&f, &fields), exchange(&f, &fields));
    let (success, rejected) = if a.0 == StatusCode::OK {
        (a, b)
    } else {
        (b, a)
    };
    assert_eq!(success.0, StatusCode::OK);
    assert_eq!(rejected.0, StatusCode::BAD_REQUEST);
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            success.1["access_token"].as_str(),
            None,
            Value::Null
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn connector_metadata_challenges_and_consent_cancel_are_bound() {
    let f = Fixture::new().await;
    let (_, meta) = req(
        &f.app,
        "GET",
        "/.well-known/oauth-authorization-server",
        None,
        None,
        None,
        Value::Null,
    )
    .await;
    assert_eq!(meta["issuer"], ORIGIN);
    assert_eq!(meta["code_challenge_methods_supported"], json!(["S256"]));
    assert_eq!(
        meta["token_endpoint_auth_methods_supported"],
        json!(["none"])
    );
    assert_eq!(meta["client_id_metadata_document_supported"], true);
    assert_eq!(meta["authorization_response_iss_parameter_supported"], true);
    let (_, resource) = req(
        &f.app,
        "GET",
        "/.well-known/oauth-protected-resource/mcp",
        None,
        None,
        None,
        Value::Null,
    )
    .await;
    assert_eq!(resource["resource"], format!("{ORIGIN}/mcp"));
    assert_eq!(resource["authorization_servers"], json!([ORIGIN]));
    let r = f
        .app
        .clone()
        .oneshot(Request::builder().uri("/mcp").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(r.status(), 401);
    let challenge = r.headers()["www-authenticate"].to_str().unwrap();
    assert!(challenge.contains(
        "resource_metadata=\"https://zoop.example/.well-known/oauth-protected-resource/mcp\""
    ));
    assert!(
        challenge
            .contains("scope=\"sleep:read recovery:read activity:read weight:read goals:read\"")
    );
    let (_, a) = authorization(&f).await;
    let (status, v) = req(
        &f.app,
        "POST",
        "/v1/agent-authorization/deny",
        Some(&f.owner),
        None,
        Some(ORIGIN),
        a.clone(),
    )
    .await;
    assert_eq!(status, 200);
    let u = url::Url::parse(v["redirect_to"].as_str().unwrap()).unwrap();
    let fields: std::collections::HashMap<_, _> = u.query_pairs().collect();
    assert_eq!(fields.get("iss").unwrap(), ORIGIN);
    assert_eq!(fields.get("state").unwrap(), "client-state");
    assert_eq!(fields.get("error").unwrap(), "access_denied");
    assert_eq!(
        f.db.count("SELECT count(*) FROM agent_connections").await,
        0
    );
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent-authorization/deny",
            Some(&f.owner),
            None,
            Some("https://evil.example"),
            a.clone()
        )
        .await
        .0,
        403
    );
    let mut bad = a;
    bad["redirect_uri"] = json!("https://evil.example/callback");
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/v1/agent-authorization/deny",
            Some(&f.owner),
            None,
            Some(ORIGIN),
            bad
        )
        .await
        .0,
        400
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn registration_cleanup_and_limits_preserve_connected_clients() {
    let f = Fixture::new().await;
    let (id, a) = authorization(&f).await;
    approve(&f, a).await;
    f.db.store
        .register_agent_client("abandoned", "Unused", &["https://client.example/cb".into()])
        .await
        .unwrap();
    f.db.sql("UPDATE agent_clients SET created_at=now()-interval '8 days'")
        .await;
    f.db.store.purge_unused_agent_clients().await.unwrap();
    assert!(f.db.store.agent_client(&id).await.unwrap().is_some());
    assert!(
        f.db.store
            .agent_client("abandoned")
            .await
            .unwrap()
            .is_none()
    );
    for _ in 0..29 {
        let (status, _) = req(
            &f.app,
            "POST",
            "/oauth/register",
            None,
            None,
            None,
            json!({"client_name":"Test","redirect_uris":["https://client.example/cb"]}),
        )
        .await;
        assert_eq!(status, 201);
    }
    assert_eq!(
        req(
            &f.app,
            "POST",
            "/oauth/register",
            None,
            None,
            None,
            json!({"client_name":"Test","redirect_uris":["https://client.example/cb"]})
        )
        .await
        .0,
        429
    );
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn token_expiry_audience_and_malformed_requests_fail_closed() {
    let f = Fixture::new().await;
    let (id, a) = authorization(&f).await;
    let code = approve(&f, a).await;
    let fields = [
        ("grant_type", "authorization_code"),
        ("client_id", id.as_str()),
        ("resource", "https://zoop.example/mcp"),
        ("code", code.as_str()),
        ("redirect_uri", "http://127.0.0.1:9000/callback"),
        ("code_verifier", VERIFIER),
    ];
    let (status, t) = exchange(&f, &fields).await;
    assert_eq!(status, 200);
    assert!(t["expires_in"].as_i64().unwrap() <= 3600);
    assert!(t["expires_in"].as_i64().unwrap() > 3500);
    assert_eq!(f.db.count("SELECT count(*) FROM agent_credentials WHERE kind='refresh' AND expires_at <= now()+interval '30 days' AND expires_at > now()+interval '29 days'").await,1);
    assert!(
        f.db.store
            .authenticate_agent(
                &digest(t["access_token"].as_str().unwrap()),
                "https://other.example/mcp"
            )
            .await
            .unwrap()
            .is_none()
    );
    f.db.sql(
        "UPDATE agent_credentials SET expires_at=now()-interval '1 second' WHERE kind='refresh'",
    )
    .await;
    let (status, error) = exchange(
        &f,
        &[
            ("grant_type", "refresh_token"),
            ("client_id", &id),
            ("resource", "https://zoop.example/mcp"),
            ("refresh_token", t["refresh_token"].as_str().unwrap()),
        ],
    )
    .await;
    assert_eq!(status, 400);
    assert_eq!(error["error"], "invalid_grant");
    let (status, error) = exchange(&f, &[("grant_type", "authorization_code")]).await;
    assert_eq!(status, 400);
    assert_eq!(error["error"], "invalid_request");
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn authorization_error_issuer_and_native_callback_ports() {
    let f = Fixture::new().await;
    let (_, a) = authorization(&f).await;
    let mut bad = a.clone();
    bad["code_challenge_method"] = json!("plain");
    let query = |a: &Value| {
        let mut q = url::form_urlencoded::Serializer::new(String::new());
        for (k, v) in a.as_object().unwrap() {
            if let Some(v) = v.as_str() {
                q.append_pair(k, v);
            }
        }
        q.finish()
    };
    // ChatGPT adds a language preference to the authorization request. Only
    // supported fields should make it as far as Zoop's consent screen.
    let request = format!("{}&ui_locales=en-US%20el&display=popup", query(&a));
    let r = f
        .app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/oauth/authorize?{request}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(r.status().is_redirection());
    let location = url::Url::parse(r.headers()["location"].to_str().unwrap()).unwrap();
    assert_eq!(location.origin().ascii_serialization(), ORIGIN);
    let consent_query = location
        .fragment()
        .unwrap()
        .strip_prefix("agent-authorize?")
        .unwrap();
    let forwarded: std::collections::BTreeMap<_, _> =
        url::form_urlencoded::parse(consent_query.as_bytes())
            .into_owned()
            .collect();
    assert_eq!(serde_json::to_value(forwarded).unwrap(), a);
    let r = f
        .app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/oauth/authorize?{}", query(&bad)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(r.status().is_redirection());
    let callback = url::Url::parse(r.headers()["location"].to_str().unwrap()).unwrap();
    let fields: std::collections::HashMap<_, _> = callback.query_pairs().collect();
    assert_eq!(fields.get("iss").unwrap(), ORIGIN);
    assert_eq!(fields.get("error").unwrap(), "invalid_request");
    bad["redirect_uri"] = json!("https://evil.example/cb");
    let r = f
        .app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/oauth/authorize?{}", query(&bad)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r.status(), 400);
    assert!(r.headers().get("location").is_none());
    let (_, registered) = req(
        &f.app,
        "POST",
        "/oauth/register",
        None,
        None,
        None,
        json!({"client_name":"Native test","redirect_uris":["http://localhost/callback"]}),
    )
    .await;
    let id = registered["client_id"].as_str().unwrap();
    let mut native = a;
    native["client_id"] = json!(id);
    native["redirect_uri"] = json!("http://localhost:34567/callback");
    let code = approve(&f, native).await;
    let mut fields = [
        ("grant_type", "authorization_code"),
        ("client_id", id),
        ("resource", "https://zoop.example/mcp"),
        ("code", code.as_str()),
        ("redirect_uri", "http://localhost:34568/callback"),
        ("code_verifier", VERIFIER),
    ];
    assert_eq!(exchange(&f, &fields).await.0, 400);
    fields[4].1 = "http://localhost:34567/callback";
    assert_eq!(exchange(&f, &fields).await.0, 200);
}

#[tokio::test]
#[ignore = "requires isolated development Postgres"]
async fn simultaneous_refresh_reuse_revokes_the_connection() {
    let f = Fixture::new().await;
    let (id, a) = authorization(&f).await;
    let code = approve(&f, a).await;
    let (_, token) = exchange(
        &f,
        &[
            ("grant_type", "authorization_code"),
            ("client_id", &id),
            ("resource", "https://zoop.example/mcp"),
            ("code", &code),
            ("redirect_uri", "http://127.0.0.1:9000/callback"),
            ("code_verifier", VERIFIER),
        ],
    )
    .await;
    let fields = [
        ("grant_type", "refresh_token"),
        ("client_id", id.as_str()),
        ("resource", "https://zoop.example/mcp"),
        ("refresh_token", token["refresh_token"].as_str().unwrap()),
    ];
    let (a, b) = tokio::join!(exchange(&f, &fields), exchange(&f, &fields));
    let (ok, bad) = if a.0 == 200 { (a, b) } else { (b, a) };
    assert_eq!(ok.0, 200);
    assert_eq!(bad.0, 400);
    assert_eq!(bad.1["error"], "invalid_grant");
    assert_eq!(
        req(
            &f.app,
            "GET",
            "/v1/agent/available_data",
            None,
            ok.1["access_token"].as_str(),
            None,
            Value::Null
        )
        .await
        .0,
        401
    );
}
