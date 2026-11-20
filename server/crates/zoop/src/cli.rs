use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "zoop", about = "Self-hosted backend for WHOOP 5.0 / MG straps")]
pub(crate) struct Cli {
    #[command(subcommand)]
    pub(crate) command: Option<Command>,
    /// Path to the TOML configuration file.
    #[arg(long, default_value = "zoop.toml", global = true)]
    pub(crate) config: PathBuf,
}

#[derive(Debug, Subcommand)]
pub(crate) enum Command {
    /// Run the API server and the decode worker (default).
    Run,
    /// Probe local API and worker readiness for container health checks.
    Healthcheck,
    /// Provision or recover a private account (operator-only, no public registration).
    Account {
        #[command(subcommand)]
        action: AccountCommand,
    },
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
    /// Detect one day's workouts for one device, store them, and print them as JSON.
    AnalyzeWorkouts {
        /// Strap serial.
        #[arg(long)]
        device: String,
        /// Local calendar day, YYYY-MM-DD, in the profile's time zone. Defaults to today.
        #[arg(long)]
        day: Option<chrono::NaiveDate>,
    },
}

#[derive(Debug, Subcommand)]
pub(crate) enum AccountCommand {
    /// Create an account. Passwords are read from a protected file, never arguments.
    Create {
        #[arg(long)]
        email: String,
        #[arg(long)]
        /// Protected file, or - to read the password from standard input.
        password_file: PathBuf,
        #[arg(long)]
        admin: bool,
    },
    /// Reserve a device for an account, including before its first upload.
    BindDevice {
        #[arg(long)]
        email: String,
        #[arg(long)]
        device: String,
    },
    /// Import a protected iPhone token file; it becomes scoped to this account.
    ImportToken {
        #[arg(long)]
        email: String,
        #[arg(long)]
        token_file: PathBuf,
    },
    /// Reset password and revoke browser sessions and iPhone tokens.
    ResetPassword {
        #[arg(long)]
        email: String,
        #[arg(long)]
        /// Protected file, or - to read the password from standard input.
        password_file: PathBuf,
    },
    /// Disable all account access and revoke tokens and sessions.
    Disable {
        #[arg(long)]
        email: String,
    },
}
