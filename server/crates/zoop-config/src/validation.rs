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
        if self.web.enabled {
            let valid = url::Url::parse(&self.web.origin).is_ok_and(|u| {
                matches!(u.scheme(), "https" | "http")
                    && u.host_str().is_some()
                    && u.username().is_empty()
                    && u.password().is_none()
                    && u.query().is_none()
                    && u.fragment().is_none()
                    && u.path() == "/"
                    && !self.web.origin.ends_with('/')
            });
            if !valid {
                issues.push(ValidationIssue{level:IssueLevel::Error,message:"web.origin must be an HTTP or HTTPS origin without path, credentials, query or fragment".into()});
            }
        }
        if self.web.setup_token.as_ref().is_some_and(|token| {
            !self.web.enabled || !(32..=256).contains(&token.expose_secret().len())
        }) {
            issues.push(ValidationIssue {
                level: IssueLevel::Error,
                message: "web.setup_token requires private accounts and 32–256 bytes".into(),
            });
        }
        let token = self.server_config.ingest_token.expose_secret();

        if token.is_empty() {
            issues.push(ValidationIssue {
                level: IssueLevel::Error,
                message: "server.ingest_token is empty".to_owned(),
            });
        } else if token.starts_with(DEV_TOKEN_PREFIX) || token.len() < MIN_TOKEN_LEN {
            issues.push(ValidationIssue {
                level: if self.server_config.bind.parse::<std::net::SocketAddr>().is_ok_and(|addr| addr.ip().is_loopback()) { IssueLevel::Warn } else { IssueLevel::Error },
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
