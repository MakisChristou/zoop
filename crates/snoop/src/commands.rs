use anyhow::{Context, bail};
use chrono::{NaiveDate, Utc};
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

pub(crate) async fn analyze(
    config: &StorageConfig,
    device: &str,
    night: Option<NaiveDate>,
) -> anyhow::Result<()> {
    let store = PostgresStore::connect(config.postgres_url.expose_secret())
        .await
        .context("connecting to Postgres")?;
    let night = night.unwrap_or_else(|| Utc::now().date_naive());
    match snoop_core::analyze_night(&store, device, night).await? {
        Some(result) => println!("{}", serde_json::to_string_pretty(&result)?),
        None => println!("{{\"night_of\": \"{night}\", \"sleep\": null}}"),
    }
    Ok(())
}

pub(crate) async fn analyze_workouts(
    config: &StorageConfig,
    device: &str,
    day: Option<NaiveDate>,
) -> anyhow::Result<()> {
    let store = PostgresStore::connect(config.postgres_url.expose_secret())
        .await
        .context("connecting to Postgres")?;
    match snoop_core::analyze_day(&store, device, day).await? {
        Some(result) => println!("{}", serde_json::to_string_pretty(&result)?),
        None => println!("{{\"workouts\": null}}"),
    }
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
