//! Public client metadata is untrusted input, including its network destination.
use crate::{
    error::{AgentError, AgentResult},
    state::AgentState,
};
use serde::Deserialize;
use std::{
    collections::HashMap,
    net::{IpAddr, SocketAddr},
    time::{Duration, Instant},
};
use tokio::sync::{Mutex, Semaphore};
use url::Url;
use zoop_storage::AgentClient;

const MAX_DOCUMENT: usize = 32 * 1024;
const MAX_CACHE: usize = 128;
#[derive(Debug)]
pub(crate) struct Registry {
    cache: Mutex<HashMap<String, (Instant, AgentClient)>>,
    fetching: Semaphore,
}
impl Default for Registry {
    fn default() -> Self {
        Self {
            cache: Mutex::new(HashMap::new()),
            fetching: Semaphore::new(4),
        }
    }
}
#[derive(Debug, Deserialize)]
struct Document {
    client_id: String,
    client_name: String,
    redirect_uris: Vec<String>,
    token_endpoint_auth_method: Option<String>,
    token_endpoint_auth_methods_supported: Option<Vec<String>>,
    grant_types: Option<Vec<String>>,
    response_types: Option<Vec<String>>,
}
fn invalid() -> AgentError {
    AgentError::Invalid("Could not verify this client's metadata.")
}
fn document(bytes: &[u8], id: &str) -> AgentResult<AgentClient> {
    if bytes.len() > MAX_DOCUMENT {
        return Err(invalid());
    }
    let d: Document = serde_json::from_slice(bytes).map_err(|_| invalid())?;
    // The plural field is capability negotiation; the singular field is a legacy
    // preference. ChatGPT advertises private_key_jwt but also supports none.
    let public = match d.token_endpoint_auth_methods_supported {
        Some(methods) => methods.iter().any(|m| m == "none"),
        None => d.token_endpoint_auth_method.as_deref().unwrap_or("none") == "none",
    };
    if d.client_id != id
        || !public
        || !valid_name(&d.client_name)
        || d.redirect_uris.is_empty()
        || d.redirect_uris.len() > 10
        || d.redirect_uris
            .iter()
            .any(|u| !crate::oauth::valid_redirect(u))
        || d.grant_types
            .is_some_and(|v| !v.iter().any(|g| g == "authorization_code"))
        || d.response_types
            .is_some_and(|v| !v.iter().any(|g| g == "code"))
    {
        return Err(invalid());
    }
    Ok(AgentClient {
        id: id.into(),
        name: d.client_name,
        redirect_uris: d.redirect_uris,
    })
}
pub(crate) fn valid_name(s: &str) -> bool {
    !s.trim().is_empty() && s.len() <= 80 && !s.chars().any(char::is_control)
}
fn metadata_url(id: &str) -> AgentResult<Url> {
    let u = Url::parse(id).map_err(|_| invalid())?;
    if id.len() > 2048
        || u.scheme() != "https"
        || u.path() == "/"
        || u.host_str().is_none()
        || !u.username().is_empty()
        || u.password().is_some()
        || u.fragment().is_some()
        || u.port_or_known_default() != Some(443)
    {
        return Err(invalid());
    }
    Ok(u)
}
fn public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => {
            let [a, b, c, _] = v.octets();
            !(a == 0
                || a == 10
                || a == 127
                || a >= 224
                || (a == 100 && (64..=127).contains(&b))
                || (a == 169 && b == 254)
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192
                    && (b == 168 || (b == 0 && (c == 0 || c == 2)) || (b == 88 && c == 99)))
                || (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)))
                || (a == 203 && b == 0 && c == 113))
        }
        IpAddr::V6(v) => {
            let [a, b, ..] = v.segments();
            // Only native global unicast. Reject mapped IPv4, transition routes,
            // documentation, benchmark and protocol-assignment destinations.
            (a & 0xe000) == 0x2000
                && !(a == 0x2001 && (b <= 0x1ff || b == 0xdb8))
                && a != 0x2002
                && !(a == 0x3fff && b < 0x1000)
        }
    }
}
fn cache_seconds(headers: &reqwest::header::HeaderMap) -> u64 {
    let directives = headers
        .get("cache-control")
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");
    let mut ttl = 300;
    for part in directives.split(',').map(str::trim) {
        if ["no-store", "no-cache", "private"]
            .iter()
            .any(|d| part.eq_ignore_ascii_case(d))
        {
            return 0;
        }
        if let Some((name, value)) = part.split_once('=')
            && name.eq_ignore_ascii_case("max-age")
        {
            ttl = value
                .trim_matches('"')
                .parse::<u64>()
                .unwrap_or(0)
                .min(3600);
        }
    }
    ttl.saturating_sub(
        headers
            .get("age")
            .and_then(|h| h.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0),
    )
}
async fn fetch(id: &str) -> AgentResult<(AgentClient, u64)> {
    let u = metadata_url(id)?;
    let host = u.host_str().ok_or_else(invalid)?;
    let addresses: Vec<SocketAddr> = tokio::net::lookup_host((host, 443))
        .await
        .map_err(|_| invalid())?
        .take(33)
        .collect();
    if addresses.is_empty() || addresses.len() > 32 || addresses.iter().any(|a| !public_ip(a.ip()))
    {
        return Err(invalid());
    }
    // Resolve once, validate every address, pin the connection to that set. A new
    // client avoids pooled connections, proxy environment variables and DNS rebinding.
    let http = reqwest::Client::builder()
        .user_agent("Zoop/0.1 OAuth metadata")
        .https_only(true)
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .resolve_to_addrs(host, &addresses)
        .connect_timeout(Duration::from_secs(3))
        .timeout(Duration::from_secs(6))
        .build()
        .map_err(|_| AgentError::Unavailable)?;
    let mut response = http
        .get(u)
        .header("accept", "application/json")
        .send()
        .await
        .map_err(|_| invalid())?;
    if response.status() != reqwest::StatusCode::OK
        || response
            .content_length()
            .is_some_and(|n| n > MAX_DOCUMENT as u64)
        || response.headers().contains_key("content-encoding")
        || !response
            .headers()
            .get("content-type")
            .and_then(|h| h.to_str().ok())
            .is_some_and(|s| {
                s.split(';')
                    .next()
                    .is_some_and(|m| m.trim() == "application/json")
            })
    {
        return Err(invalid());
    }
    let ttl = cache_seconds(response.headers());
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| invalid())? {
        if bytes.len() + chunk.len() > MAX_DOCUMENT {
            return Err(invalid());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok((document(&bytes, id)?, ttl))
}
pub(crate) async fn resolve(s: &AgentState, id: &str) -> AgentResult<AgentClient> {
    if !id.starts_with("https://") {
        return s
            .store
            .agent_client(id)
            .await?
            .ok_or(AgentError::Invalid("Unknown client. Register it first."));
    }
    metadata_url(id)?;
    {
        let mut cache = s.clients.cache.lock().await;
        cache.retain(|_, (expiry, _)| *expiry > Instant::now());
        if let Some((_, c)) = cache.get(id) {
            return Ok(c.clone());
        }
    }
    let _slot = s
        .clients
        .fetching
        .try_acquire()
        .map_err(|_| AgentError::Limited)?;
    if !s.store.allow_login("agent-metadata", 120, 60).await? {
        return Err(AgentError::Limited);
    }
    let (client, ttl) = tokio::time::timeout(Duration::from_secs(8), fetch(id))
        .await
        .map_err(|_| invalid())??;
    if ttl > 0 {
        let mut cache = s.clients.cache.lock().await;
        if cache.len() >= MAX_CACHE {
            cache.clear();
        }
        cache.insert(
            id.into(),
            (Instant::now() + Duration::from_secs(ttl), client.clone()),
        );
    }
    Ok(client)
}
/// Only RFC8252 loopback callback ports vary; host, path and query stay exact.
pub(crate) fn redirect_matches(registered: &str, actual: &str) -> bool {
    if registered == actual {
        return true;
    }
    let (Ok(mut r), Ok(mut a)) = (Url::parse(registered), Url::parse(actual)) else {
        return false;
    };
    if r.scheme() != "http"
        || a.scheme() != "http"
        || r.host_str() != a.host_str()
        || !matches!(r.host_str(), Some("localhost" | "127.0.0.1"))
        || r.path() != "/callback"
        || !crate::oauth::valid_redirect(actual)
    {
        return false;
    }
    let _ = r.set_port(None);
    let _ = a.set_port(None);
    r == a
}
#[cfg(test)]
mod tests;
