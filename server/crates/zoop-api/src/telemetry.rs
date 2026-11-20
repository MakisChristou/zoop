//! Bounded process-local HTTP statistics. Never records paths or payloads.
use crate::AppState;
use axum::{
    extract::{Request, State},
    http::{HeaderValue, header},
    middleware::Next,
    response::Response,
};
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::Instant,
};
#[derive(Debug)]
pub(crate) struct Telemetry {
    start: Instant,
    requests: AtomicU64,
    errors: AtomicU64,
    durations: Mutex<VecDeque<f64>>,
}
impl Default for Telemetry {
    fn default() -> Self {
        Self {
            start: Instant::now(),
            requests: AtomicU64::new(0),
            errors: AtomicU64::new(0),
            durations: Mutex::new(VecDeque::new()),
        }
    }
}
impl Telemetry {
    pub(crate) fn snapshot(&self) -> Value {
        let p95 = self.durations.lock().ok().and_then(|q| {
            if q.is_empty() {
                return None;
            }
            let mut v: Vec<_> = q.iter().copied().collect();
            v.sort_by(f64::total_cmp);
            Some(v[((v.len() * 95).div_ceil(100) - 1).min(v.len() - 1)])
        });
        json!({"uptime_seconds":self.start.elapsed().as_secs(),"requests_since_start":self.requests.load(Ordering::Relaxed),"server_errors_since_start":self.errors.load(Ordering::Relaxed),"p95_ms_recent_2048":p95})
    }
}
pub(crate) async fn observe(State(s): State<AppState>, request: Request, next: Next) -> Response {
    let start = Instant::now();
    let mut response = next.run(request).await;
    s.telemetry.requests.fetch_add(1, Ordering::Relaxed);
    if response.status().is_server_error() {
        s.telemetry.errors.fetch_add(1, Ordering::Relaxed);
    }
    if let Ok(mut q) = s.telemetry.durations.lock() {
        if q.len() >= 2048 {
            q.pop_front();
        }
        q.push_back(start.elapsed().as_secs_f64() * 1000.0);
    }
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response.headers_mut().insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response
}
