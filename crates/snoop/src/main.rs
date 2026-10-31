use anyhow::Context;
use clap::Parser;
use snoop_config::Config;
use tracing::info;
use tracing_subscriber::EnvFilter;

mod cli;
mod commands;
mod service;

use cli::{Cli, Command};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let cli = Cli::parse();
    info!("snoop starting");
    let config = Config::load(&cli.config)
        .with_context(|| format!("loading config from {}", cli.config.display()))?;

    match cli.command.unwrap_or(Command::Run) {
        Command::Run => service::run(config).await,
        Command::Validate => commands::validate(&config),
        Command::Migrate => commands::migrate(&config.storage_config).await,
        Command::Analyze { device, night } => {
            commands::analyze(&config.storage_config, &device, night).await
        }
        Command::AnalyzeWorkouts { device, day } => {
            commands::analyze_workouts(&config.storage_config, &device, day).await
        }
    }
}
