use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "snoop", about = "Self-hosted WHOOP MG backend")]
pub(crate) struct Cli {
    #[command(subcommand)]
    pub(crate) command: Option<Command>,
    /// Path to the TOML configuration file.
    #[arg(long, default_value = "snoop.toml", global = true)]
    pub(crate) config: PathBuf,
}

#[derive(Debug, Subcommand)]
pub(crate) enum Command {
    /// Run the API server and the decode worker (default).
    Run,
    /// Validate the configuration file and exit.
    Validate,
    /// Apply any pending Postgres schema migrations and exit.
    Migrate,
    /// Analyse one night for one device and print the result as JSON.
    Analyze {
        /// Strap serial.
        #[arg(long)]
        device: String,
        /// Night as the morning's date, YYYY-MM-DD. Defaults to today (UTC).
        #[arg(long)]
        night: Option<chrono::NaiveDate>,
    },
}
