use anyhow::bail;
use secrecy::ExposeSecret;
use snoop_config::{Config, IssueLevel, StorageConfig};
use snoop_storage::PostgresStore;
use tracing::{info, warn};

pub(crate) async fn migrate(config: &StorageConfig) -> anyhow::Result<()> {
    info!("applying Postgres migrations");
    PostgresStore::migrate(config.postgres_url.expose_secret()).await?;
    info!("Postgres migrations applied");
    Ok(())
}

pub(crate) fn validate(config: &Config) -> anyhow::Result<()> {
    let issues = config.validate();
    let mut errors = 0;
    for issue in &issues {
        match issue.level {
            IssueLevel::Warn => warn!("{issue}"),
            IssueLevel::Error => {
                errors += 1;
                tracing::error!("{issue}");
            }
        }
    }
    if errors > 0 {
        bail!("configuration has {errors} error(s)");
    }
    info!("configuration valid");
    Ok(())
}
