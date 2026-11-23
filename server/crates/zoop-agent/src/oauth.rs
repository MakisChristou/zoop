//! Local OAuth authorization code + S256 PKCE; no external identity provider.
use crate::{
    auth::browser,
    error::{AgentError, AgentResult},
    permissions::{Consent, SCOPES},
    state::AgentState,
};
use axum::{
    Form, Json,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Redirect, Response},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{Duration, Utc};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use url::Url;
use zoop_auth::{digest, random_token};
use zoop_storage::{AgentCredential, AgentExchange, NewAgentConnection};

#[derive(Debug, Deserialize)]
pub(crate) struct Registration {
    client_name: String,
    redirect_uris: Vec<String>,
    token_endpoint_auth_method: Option<String>,
    grant_types: Option<Vec<String>>,
    response_types: Option<Vec<String>>,
}
pub(crate) fn valid_redirect(value: &str) -> bool {
    let Ok(u) = Url::parse(value) else {
        return false;
    };
    value.len() <= 2048
        && u.host_str().is_some()
        && u.username().is_empty()
        && u.password().is_none()
        && u.fragment().is_none()
        && (u.scheme() == "https"
            || (u.scheme() == "http"
                && matches!(u.host_str(), Some("127.0.0.1" | "[::1]" | "localhost"))))
}
pub(crate) async fn register(
    State(s): State<AgentState>,
    Json(r): Json<Registration>,
) -> AgentResult<Response> {
    if r.client_name.trim().is_empty()
        || r.client_name.len() > 80
        || r.client_name.chars().any(char::is_control)
        || r.redirect_uris.is_empty()
        || r.redirect_uris.len() > 5
        || r.redirect_uris.iter().any(|u| !valid_redirect(u))
        || r.token_endpoint_auth_method
            .as_deref()
            .is_some_and(|m| m != "none")
        || r.grant_types.as_ref().is_some_and(|v| {
            v.iter()
                .any(|s| s != "authorization_code" && s != "refresh_token")
        })
        || r.response_types.as_ref().is_some_and(|v| v != &["code"])
    {
        return Err(AgentError::Invalid("Invalid public client registration."));
    }
    if !s.store.allow_login("agent-register", 30, 3600).await? {
        return Err(AgentError::Limited);
    }
    let id = random_token().map_err(|_| AgentError::Unavailable)?;
    s.store
        .register_agent_client(&id, r.client_name.trim(), &r.redirect_uris)
        .await?;
    Ok((StatusCode::CREATED,Json(json!({"client_id":id,"client_name":r.client_name,"redirect_uris":r.redirect_uris,"token_endpoint_auth_method":"none","grant_types":["authorization_code","refresh_token"],"response_types":["code"]}))).into_response())
}
pub(crate) async fn metadata(State(s): State<AgentState>) -> Json<Value> {
    Json(
        json!({"issuer":s.origin,"authorization_endpoint":format!("{}/oauth/authorize",s.origin),"token_endpoint":format!("{}/oauth/token",s.origin),"registration_endpoint":format!("{}/oauth/register",s.origin),"response_types_supported":["code"],"grant_types_supported":["authorization_code","refresh_token"],"code_challenge_methods_supported":["S256"],"token_endpoint_auth_methods_supported":["none"],"scopes_supported":SCOPES}),
    )
}
pub(crate) async fn resource_metadata(State(s): State<AgentState>) -> Json<Value> {
    Json(
        json!({"resource":s.resource(),"authorization_servers":[s.origin],"scopes_supported":SCOPES,"bearer_methods_supported":["header"],"resource_name":"Zoop health data"}),
    )
}
#[derive(Debug, Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Authorization {
    client_id: String,
    redirect_uri: String,
    response_type: String,
    code_challenge: String,
    code_challenge_method: String,
    resource: String,
    scope: Option<String>,
    state: Option<String>,
}
impl Authorization {
    async fn validate(&self, s: &AgentState) -> AgentResult<String> {
        if self.client_id.len() > 128
            || self.response_type != "code"
            || self.code_challenge_method != "S256"
            || self.code_challenge.len() != 43
            || !self
                .code_challenge
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
            || self.resource != s.resource()
            || self.state.as_ref().is_some_and(|v| v.len() > 1024)
            || self.scope.as_ref().is_some_and(|v| {
                v.len() > 200 || v.split_whitespace().any(|x| !SCOPES.contains(&x))
            })
        {
            return Err(AgentError::Invalid("Invalid authorization request."));
        }
        let client = s
            .store
            .agent_client(&self.client_id)
            .await?
            .ok_or(AgentError::Invalid("Unknown client. Register it first."))?;
        if !client.redirect_uris.contains(&self.redirect_uri) {
            return Err(AgentError::Invalid(
                "Callback does not match the registered client.",
            ));
        }
        Ok(client.name)
    }
}
pub(crate) async fn authorize(
    State(s): State<AgentState>,
    Query(a): Query<Authorization>,
) -> AgentResult<Redirect> {
    a.validate(&s).await?;
    let mut dest = Url::parse(&format!("{}/", s.origin)).map_err(|_| AgentError::Unavailable)?;
    let mut params = url::form_urlencoded::Serializer::new(String::new());
    let value = serde_json::to_value(&a).map_err(|_| AgentError::Unavailable)?;
    if let Some(fields) = value.as_object() {
        for (k, v) in fields {
            if let Some(v) = v.as_str() {
                params.append_pair(k, v);
            }
        }
    }
    dest.set_fragment(Some(&format!("agent-authorize?{}", params.finish())));
    Ok(Redirect::to(dest.as_str()))
}
pub(crate) async fn details(
    State(s): State<AgentState>,
    h: HeaderMap,
    Query(a): Query<Authorization>,
) -> AgentResult<Json<Value>> {
    browser(&s, &h, false).await?;
    let name = a.validate(&s).await?;
    Ok(Json(
        json!({"client_name":name,"redirect_uri":a.redirect_uri,"scopes":a.scope.unwrap_or_else(||SCOPES.join(" ")).split_whitespace().collect::<Vec<_>>()}),
    ))
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Approval {
    authorization: Authorization,
    consent: Consent,
}
pub(crate) async fn approve(
    State(s): State<AgentState>,
    h: HeaderMap,
    Json(a): Json<Approval>,
) -> AgentResult<Json<Value>> {
    let (owner, session) = browser(&s, &h, true).await?;
    let name = a.authorization.validate(&s).await?;
    a.consent.validate(&s).await?;
    let requested = a.authorization.scope.as_deref().unwrap_or("");
    if a.authorization.scope.is_some()
        && a.consent
            .scopes
            .iter()
            .any(|v| !requested.split_whitespace().any(|x| x == v))
    {
        return Err(AgentError::Forbidden);
    }
    if !s
        .store
        .allow_login(&format!("agent-create:{}", owner.id), 20, 3600)
        .await?
    {
        return Err(AgentError::Limited);
    }
    let code = random_token().map_err(|_| AgentError::Unavailable)?;
    let hash = digest(&code);
    let n = NewAgentConnection {
        account_id: owner.id,
        device: &a.consent.device_id,
        name: &name,
        scopes: &a.consent.scopes,
        history_days: a.consent.history_days,
        timezone: &a.consent.timezone,
        client_id: Some(&a.authorization.client_id),
        resource: &a.authorization.resource,
        expires_at: Utc::now() + Duration::days(a.consent.expires_in_days),
    };
    let cred = AgentCredential {
        digest: &hash,
        kind: "code",
        expires_at: Utc::now() + Duration::minutes(2),
        redirect_uri: Some(&a.authorization.redirect_uri),
        challenge: Some(&a.authorization.code_challenge),
    };
    s.store
        .create_agent_connection(&n, &session, &cred)
        .await?
        .ok_or(AgentError::Forbidden)?;
    let mut callback =
        Url::parse(&a.authorization.redirect_uri).map_err(|_| AgentError::Unavailable)?;
    callback.query_pairs_mut().append_pair("code", &code);
    if let Some(state) = a.authorization.state {
        callback.query_pairs_mut().append_pair("state", &state);
    }
    Ok(Json(json!({"redirect_to":callback.as_str()})))
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct TokenRequest {
    grant_type: String,
    client_id: String,
    resource: String,
    code: Option<String>,
    redirect_uri: Option<String>,
    code_verifier: Option<String>,
    refresh_token: Option<String>,
    scope: Option<String>,
}
pub(crate) async fn token(
    State(s): State<AgentState>,
    h: HeaderMap,
    Form(t): Form<TokenRequest>,
) -> Response {
    match exchange(&s, &h, t).await {
        Ok(v) => Json(v).into_response(),
        Err(e) => {
            let status = if matches!(e, AgentError::Limited) {
                StatusCode::TOO_MANY_REQUESTS
            } else if matches!(e, AgentError::Unavailable) {
                StatusCode::SERVICE_UNAVAILABLE
            } else {
                StatusCode::BAD_REQUEST
            };
            (status,Json(json!({"error":if status==StatusCode::BAD_REQUEST{"invalid_grant"}else{"temporarily_unavailable"}}))).into_response()
        }
    }
}
async fn exchange(s: &AgentState, h: &HeaderMap, t: TokenRequest) -> AgentResult<Value> {
    if h.contains_key("cookie")
        || h.contains_key("authorization")
        || h.get("origin")
            .is_some_and(|v| v.to_str().ok() != Some(s.origin.as_str()))
        || t.client_id.len() > 128
        || t.resource != s.resource()
        || t.scope.is_some()
    {
        return Err(AgentError::Forbidden);
    }
    if !s.store.allow_login("agent-exchange", 120, 60).await? {
        return Err(AgentError::Limited);
    }
    let kind = match t.grant_type.as_str() {
        "authorization_code" => "code",
        "refresh_token" => "refresh",
        _ => return Err(AgentError::Forbidden),
    };
    let presented = if kind == "code" {
        t.code.as_deref()
    } else {
        t.refresh_token.as_deref()
    }
    .filter(|v| v.len() <= 128)
    .ok_or(AgentError::Unauthorized)?;
    let challenge = if kind == "code" {
        let verifier = t
            .code_verifier
            .as_deref()
            .filter(|v| {
                (43..=128).contains(&v.len())
                    && v.bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"-._~".contains(&b))
            })
            .ok_or(AgentError::Unauthorized)?;
        Some(URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes())))
    } else {
        None
    };
    let access = format!(
        "zoop_at_{}",
        random_token().map_err(|_| AgentError::Unavailable)?
    );
    let refresh = format!(
        "zoop_rt_{}",
        random_token().map_err(|_| AgentError::Unavailable)?
    );
    let g = s
        .store
        .exchange_agent_credential(&AgentExchange {
            digest: &digest(presented),
            kind,
            client_id: &t.client_id,
            resource: &t.resource,
            redirect_uri: t.redirect_uri.as_deref(),
            challenge: challenge.as_deref(),
            access: &digest(&access),
            refresh: &digest(&refresh),
        })
        .await?
        .ok_or(AgentError::Unauthorized)?;
    Ok(
        json!({"access_token":access,"token_type":"Bearer","expires_in":(g.expires_at-Utc::now()).num_seconds().clamp(0,900),"refresh_token":refresh,"scope":g.scopes.join(" ")}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn callbacks_are_explicit_web_or_loopback() {
        for u in [
            "https://client.example/callback",
            "http://127.0.0.1:1234/callback",
            "http://[::1]:1234/callback",
        ] {
            assert!(valid_redirect(u), "{u}");
        }
        for u in [
            "javascript:alert(1)",
            "https://user:pass@client.example/cb",
            "https://client.example/cb#x",
            "http://attacker.example/cb",
            "https://",
        ] {
            assert!(!valid_redirect(u), "{u}");
        }
    }
}
