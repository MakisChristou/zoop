//! A branding upgrade must keep existing server environment configuration usable.
use std::process::Command;

#[test]
fn legacy_environment_works_and_new_names_take_precedence() {
    let path = std::env::temp_dir().join(format!("zoop-config-{}.toml", std::process::id()));
    std::fs::write(&path, include_str!("../../../zoop.dev.toml")).unwrap();
    let run = |legacy: Option<&str>, current: Option<&str>| {
        let mut command = Command::new(env!("CARGO_BIN_EXE_zoop"));
        command.args(["validate", "--config"]).arg(&path);
        command.env_remove("SNOOP_STORAGE__POSTGRES_URL");
        command.env_remove("ZOOP_STORAGE__POSTGRES_URL");
        if let Some(value) = legacy {
            command.env("SNOOP_STORAGE__POSTGRES_URL", value);
        }
        if let Some(value) = current {
            command.env("ZOOP_STORAGE__POSTGRES_URL", value);
        }
        command.output().unwrap().status.success()
    };
    let valid = "postgres://localhost/unused";
    let invalid = "mysql://localhost/unused";
    let results = [
        run(Some(valid), None),
        run(Some(invalid), None),
        run(Some(invalid), Some(valid)),
        run(Some(valid), Some(invalid)),
    ];
    std::fs::remove_file(&path).unwrap();
    assert_eq!(results, [true, false, true, false]);
}
