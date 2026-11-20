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
bind = "127.0.0.1:8080"
ingest_token = "dev-token"

[storage]
postgres_url = "postgres://zoop:zoop@localhost:5432/zoop"
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
bind = "127.0.0.1:8080"
ingest_token = "0123456789abcdef0123456789abcdef"

[storage]
postgres_url = "mysql://nope"
"#,
    );
    let issues = Config::load(file.path()).unwrap().validate();
    assert!(issues.iter().any(|issue| issue.level == IssueLevel::Error));
}

#[test]
fn web_origin_accepts_operator_http_and_https_origins() {
    for (origin, valid) in [
        ("https://zoop.example", true),
        ("http://127.0.0.1:5173", true),
        ("http://localhost:5173", true),
        ("http://public.example", true),
        ("http://192.168.1.10:8080", true),
        ("http://[fd00::1]:8080", true),
        ("file:///tmp/zoop", false),
        ("https://zoop.example/path", false),
        ("https://zoop.example/", false),
        ("https://user:secret@zoop.example", false),
        ("https://zoop.example?x=1", false),
    ] {
        let file = write_config(&format!(
            r#"
[server]
bind="127.0.0.1:18471"
ingest_token="0123456789abcdef0123456789abcdef"
[storage]
postgres_url="postgres://localhost/zoop"
[web]
enabled=true
origin="{origin}"
"#
        ));
        assert_eq!(
            !Config::load(file.path())
                .unwrap()
                .validate()
                .iter()
                .any(|i| i.level == IssueLevel::Error),
            valid,
            "{origin}"
        );
    }
}

#[test]
fn development_token_cannot_listen_publicly() {
    let file = write_config(
        r#"[server]
bind="0.0.0.0:8471"
ingest_token="dev-token"
[storage]
postgres_url="postgres://localhost/zoop"
"#,
    );
    assert!(
        Config::load(file.path())
            .unwrap()
            .validate()
            .iter()
            .any(|i| i.level == IssueLevel::Error)
    );
}
