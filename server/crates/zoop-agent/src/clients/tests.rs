use super::*;
#[test]
fn block_internal_and_transitional_addresses() {
    for ip in [
        "127.0.0.1",
        "10.0.0.1",
        "169.254.169.254",
        "100.64.0.1",
        "172.31.0.1",
        "192.168.1.1",
        "0.0.0.0",
        "224.0.0.1",
        "198.19.0.1",
        "::1",
        "::ffff:8.8.8.8",
        "fc00::1",
        "fe80::1",
        "2002:0808:0808::1",
        "2001:db8::1",
        "2001::1",
    ] {
        assert!(!public_ip(ip.parse().unwrap()), "{ip}");
    }
    for ip in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"] {
        assert!(public_ip(ip.parse().unwrap()), "{ip}");
    }
}
#[test]
fn metadata_identity_methods_and_callback_validation() {
    let id = "https://client.example/oauth.json";
    let mut d = serde_json::json!({"client_id":id,"client_name":"Test","redirect_uris":["https://client.example/cb"],"token_endpoint_auth_method":"private_key_jwt","token_endpoint_auth_methods_supported":["none","private_key_jwt"]});
    assert!(document(d.to_string().as_bytes(), id).is_ok());
    assert!(document(d.to_string().as_bytes(), "https://evil.example/oauth.json").is_err());
    d["token_endpoint_auth_methods_supported"] = serde_json::json!(["private_key_jwt"]);
    assert!(document(d.to_string().as_bytes(), id).is_err());
    for u in [
        "http://client.example/a",
        "https://user:password@client.example/a",
        "https://client.example/",
        "https://client.example:8443/a",
        "https://client.example/a#b",
    ] {
        assert!(metadata_url(u).is_err());
    }
}
#[test]
fn only_loopback_ports_vary() {
    assert!(redirect_matches(
        "http://localhost/callback",
        "http://localhost:1234/callback"
    ));
    for a in [
        "http://127.0.0.1:1234/callback",
        "http://localhost:1234/other",
        "http://localhost:1234/callback?steal=1",
        "http://evil.example/callback",
    ] {
        assert!(!redirect_matches("http://localhost/callback", a));
    }
    assert!(!redirect_matches(
        "https://client.example/callback",
        "https://client.example:444/callback"
    ));
}
#[test]
fn bounded_cache_honours_opt_out_and_age() {
    let mut h = reqwest::header::HeaderMap::new();
    h.insert("cache-control", "max-age=100000".parse().unwrap());
    assert_eq!(cache_seconds(&h), 3600);
    h.insert("age", "3590".parse().unwrap());
    assert_eq!(cache_seconds(&h), 10);
    h.insert("cache-control", "max-age=3600, no-store".parse().unwrap());
    assert_eq!(cache_seconds(&h), 0);
}

#[tokio::test]
#[cfg(feature = "live-provider-check")]
#[ignore = "explicit live public metadata check; no credentials or health data"]
async fn hosted_provider_documents_support_public_clients() {
    for id in [
        "https://chatgpt.com/oauth/client.json",
        "https://claude.ai/oauth/mcp-oauth-client-metadata",
    ] {
        let (client, _) = tokio::time::timeout(Duration::from_secs(8), fetch(id))
            .await
            .unwrap()
            .unwrap_or_else(|e| panic!("{id}: {e}"));
        assert_eq!(client.id, id);
        assert!(!client.redirect_uris.is_empty());
    }
}

#[test]
fn invalid_documents_do_not_create_a_trusted_client() {
    let id = "https://client.example/oauth.json";
    for d in [
        serde_json::json!({"client_id":id,"client_name":"Test","redirect_uris":["javascript:alert(1)"]}),
        serde_json::json!({"client_id":id,"client_name":"Test","redirect_uris":[]}),
        serde_json::json!({"client_id":id,"client_name":"Test","redirect_uris":["https://client.example/cb"],"response_types":["token"]}),
        serde_json::json!({"client_id":id,"client_name":"Test","redirect_uris":["https://client.example/cb"],"grant_types":["client_credentials"]}),
    ] {
        assert!(document(d.to_string().as_bytes(), id).is_err());
    }
    assert!(document(b"not json", id).is_err());
}
