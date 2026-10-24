use secrecy::SecretString;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
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
