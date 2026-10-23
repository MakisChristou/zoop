use std::fmt;

use secrecy::ExposeSecret;

use crate::Config;

const DEV_TOKEN_PREFIX: &str = "dev-";
const MIN_TOKEN_LEN: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IssueLevel {
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationIssue {
    pub level: IssueLevel,
    pub message: String,
}

impl fmt::Display for ValidationIssue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let level = match self.level {
            IssueLevel::Warn => "warn",
            IssueLevel::Error => "error",
        };
        write!(f, "[{level}] {}", self.message)
    }
}

impl Config {
    /// Structural checks that need no network or database.
    pub fn validate(&self) -> Vec<ValidationIssue> {
        let mut issues = Vec::new();
        let token = self.server_config.ingest_token.expose_secret();

        if token.is_empty() {
            issues.push(ValidationIssue {
                level: IssueLevel::Error,
                message: "server.ingest_token is empty".to_owned(),
            });
        } else if token.starts_with(DEV_TOKEN_PREFIX) || token.len() < MIN_TOKEN_LEN {
            issues.push(ValidationIssue {
                level: IssueLevel::Warn,
                message: format!(
                    "server.ingest_token looks like a development value; use `openssl rand -hex {MIN_TOKEN_LEN}`"
                ),
            });
        }

        if !self
            .storage_config
            .postgres_url
            .expose_secret()
            .starts_with("postgres")
        {
            issues.push(ValidationIssue {
                level: IssueLevel::Error,
                message: "storage.postgres_url is not a Postgres URL".to_owned(),
            });
        }

        if self.worker_config.batch_size <= 0 {
            issues.push(ValidationIssue {
                level: IssueLevel::Error,
                message: "worker.batch_size must be positive".to_owned(),
            });
        }

        issues
    }
}
