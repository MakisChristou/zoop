use std::io::Write;

use crate::{Config, IssueLevel};

fn write_config(contents: &str) -> tempfile::NamedTempFile {
    let mut file = tempfile::Builder::new().suffix(".toml").tempfile().unwrap();
    file.write_all(contents.as_bytes()).unwrap();
    file
}

#[test]
fn loads_dev_config_and_warns_on_dev_token() {
    let file = write_config(
        r#"
[server]
bind = "0.0.0.0:8080"
ingest_token = "dev-token"

[storage]
postgres_url = "postgres://snoop:snoop@localhost:5432/snoop"
"#,
    );
    let config = Config::load(file.path()).unwrap();
    assert_eq!(config.worker_config.batch_size, 500);

    let issues = config.validate();
    assert_eq!(issues.len(), 1);
    assert_eq!(issues[0].level, IssueLevel::Warn);
}

#[test]
fn rejects_non_postgres_url() {
    let file = write_config(
        r#"
[server]
bind = "0.0.0.0:8080"
ingest_token = "0123456789abcdef0123456789abcdef"

[storage]
postgres_url = "mysql://nope"
"#,
    );
    let issues = Config::load(file.path()).unwrap().validate();
    assert!(issues.iter().any(|issue| issue.level == IssueLevel::Error));
}
