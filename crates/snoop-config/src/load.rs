use std::path::Path;

use figment::{
    Figment,
    providers::{Env, Format, Toml},
};

use crate::{Config, ConfigError, ConfigResult};

impl Config {
    /// Loads the TOML file, then lets `SNOOP_*` environment variables override
    /// individual keys (`SNOOP_SERVER__INGEST_TOKEN`, `SNOOP_STORAGE__POSTGRES_URL`).
    ///
    /// # Errors
    ///
    /// The file is missing, malformed, or fails to deserialize.
    pub fn load(path: impl AsRef<Path>) -> ConfigResult<Self> {
        let path = path.as_ref();

        Figment::new()
            .merge(Toml::file(path))
            .merge(Env::prefixed("SNOOP_").split("__"))
            .extract()
            .map_err(|source| ConfigError::Load {
                path: path.to_path_buf(),
                source: Box::new(source),
            })
    }
}
