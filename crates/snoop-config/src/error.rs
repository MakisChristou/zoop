use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("failed to load config from {path}: {source}")]
    Load {
        path: PathBuf,
        #[source]
        source: Box<figment::Error>,
    },
}

pub type ConfigResult<T> = Result<T, ConfigError>;
