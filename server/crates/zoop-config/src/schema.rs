use secrecy::SecretString;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub web: WebConfig,
    #[serde(rename = "server")]
    pub server_config: ServerConfig,
    #[serde(rename = "storage")]
    pub storage_config: StorageConfig,
    #[serde(rename = "worker", default)]
    pub worker_config: WorkerConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    /// Socket the HTTP API binds to.
    pub bind: String,
    /// Single-user bearer token the iOS app presents on every request.
    pub ingest_token: SecretString,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StorageConfig {
    pub postgres_url: SecretString,
}

#[derive(Debug, Clone, Deserialize)]
pub struct WorkerConfig {
    /// Pause calculation and bootstrap during a staged rollout; decoding continues.
    #[serde(default = "default_history_enabled")]
    pub history_enabled: bool,
    /// Idle sleep between decode passes.
    #[serde(default = "default_poll_interval_ms")]
    pub poll_interval_ms: u64,
    /// Raw frames decoded per pass.
    #[serde(default = "default_batch_size")]
    pub batch_size: i64,
    /// How often the trailing nights are re-analysed, in seconds.
    #[serde(default = "default_analysis_interval_s")]
    pub analysis_interval_s: u64,
}

impl Default for WorkerConfig {
    fn default() -> Self {
        Self {
            history_enabled: true,
            poll_interval_ms: default_poll_interval_ms(),
            batch_size: default_batch_size(),
            analysis_interval_s: default_analysis_interval_s(),
        }
    }
}

const fn default_poll_interval_ms() -> u64 {
    5_000
}

const fn default_batch_size() -> i64 {
    500
}

const fn default_analysis_interval_s() -> u64 {
    900
}

const fn default_history_enabled() -> bool {
    true
}

/// Private-account browser access is disabled until an explicit migration rollout.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct WebConfig {
    /// Optional high-entropy operator code; setup is disabled once accounts exist.
    #[serde(default)]
    pub setup_token: Option<SecretString>,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub origin: String,
}
