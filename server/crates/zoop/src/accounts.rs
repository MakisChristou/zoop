//! Local operator provisioning and recovery; nothing sensitive is printed.
use crate::cli::AccountCommand;
use anyhow::{Context, ensure};
use secrecy::ExposeSecret;
use zoop_storage::PostgresStore;
fn secret(path: &std::path::Path) -> anyhow::Result<String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        ensure!(
            std::fs::metadata(path)?.permissions().mode() & 0o077 == 0,
            "credential file must not be accessible to group or others"
        );
    }
    let text = std::fs::read_to_string(path).context("reading credential file")?;
    Ok(text.trim_end_matches(['\n', '\r']).to_owned())
}
pub(crate) async fn run(
    config: &zoop_config::Config,
    action: AccountCommand,
) -> anyhow::Result<()> {
    let s = PostgresStore::connect(config.storage_config.postgres_url.expose_secret()).await?;
    match action {
        AccountCommand::Create {
            email,
            password_file,
            admin,
        } => {
            let hash = zoop_auth::hash_password(&secret(&password_file)?)?;
            s.create_account(&email, &hash, admin).await?;
        }
        AccountCommand::BindDevice { email, device } => {
            s.bind_account_device(&email, &device).await?
        }
        AccountCommand::ImportToken { email, token_file } => {
            let token = secret(&token_file)?;
            ensure!(
                (32..=512).contains(&token.len()),
                "token must contain 32 to 512 bytes"
            );
            s.add_account_token(&email, &zoop_auth::digest(&token))
                .await?;
        }
        AccountCommand::ResetPassword {
            email,
            password_file,
        } => {
            s.reset_account_password(&email, &zoop_auth::hash_password(&secret(&password_file)?)?)
                .await?
        }
        AccountCommand::Disable { email } => s.disable_account(&email).await?,
    }
    println!("Account operation completed.");
    Ok(())
}
