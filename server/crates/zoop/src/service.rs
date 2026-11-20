use std::time::Duration;

use anyhow::Context;
use secrecy::ExposeSecret;
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;
use tracing::info;
use zoop_api::AppState;
use zoop_config::Config;
use zoop_core::{Decoder, HistoryWorker};
use zoop_storage::PostgresStore;

use crate::commands;

pub(crate) async fn run(config: Config) -> anyhow::Result<()> {
    commands::validate(&config).context("configuration invalid")?;

    let cancel = CancellationToken::new();
    spawn_shutdown(cancel.clone());

    let store = PostgresStore::connect(config.storage_config.postgres_url.expose_secret())
        .await
        .context("connecting to Postgres")?;
    store.ping().await.context("pinging Postgres")?;

    if config.web.enabled {
        anyhow::ensure!(
            store
                .private_accounts_ready()
                .await
                .context("checking private-account readiness")?
                || (config.web.setup_token.is_some() && store.setup_available().await?),
            "Private accounts require an enabled admin and an owner for every existing device. Provision accounts and bind devices before enabling web access."
        );
    }
    let decoder = Decoder::new(
        store.clone(),
        config.worker_config.batch_size,
        Duration::from_millis(config.worker_config.poll_interval_ms),
    );
    let mut worker = tokio::spawn(decoder.run(cancel.clone()));
    let analysis_interval = Duration::from_secs(config.worker_config.analysis_interval_s);
    let analyzer = HistoryWorker::new(
        store.clone(),
        config.worker_config.history_enabled,
        analysis_interval,
    );
    let mut analysis = tokio::spawn(analyzer.run(cancel.clone()));

    let mut state = AppState::new(store, config.server_config.ingest_token.clone());
    if config.web.enabled {
        state = state.with_web(zoop_api::WebOptions {
            origin: config.web.origin.clone(),
            secure_cookie: config.web.origin.starts_with("https://"),
        });
    }
    if let Some(token) = config.web.setup_token {
        state = state.with_setup_token(token);
    }
    let app = zoop_api::build_router(state);
    let listener = TcpListener::bind(&config.server_config.bind)
        .await
        .with_context(|| format!("binding {}", config.server_config.bind))?;
    info!(bind = %config.server_config.bind, "API listening");

    let server_cancel = cancel.clone();
    let server = axum::serve(listener, app)
        .with_graceful_shutdown(async move { server_cancel.cancelled().await });
    let (result, finished) = tokio::select! {
        result=server => (result.context("serving API"), 0),
        result=&mut worker => (worker_exit(result, cancel.is_cancelled(), "decoder"), 1),
        result=&mut analysis => (worker_exit(result, cancel.is_cancelled(), "history"), 2),
    };
    cancel.cancel();
    if finished != 1
        && tokio::time::timeout(Duration::from_secs(10), &mut worker)
            .await
            .is_err()
    {
        worker.abort();
    }
    if finished != 2
        && tokio::time::timeout(Duration::from_secs(10), &mut analysis)
            .await
            .is_err()
    {
        analysis.abort();
    }
    result?;
    info!("zoop stopped");
    Ok(())
}

fn worker_exit(
    result: Result<zoop_core::CoreResult<()>, tokio::task::JoinError>,
    stopping: bool,
    name: &str,
) -> anyhow::Result<()> {
    result
        .with_context(|| format!("{name} task exited"))?
        .with_context(|| format!("{name} worker failed"))?;
    anyhow::ensure!(stopping, "{name} worker exited unexpectedly");
    Ok(())
}

fn spawn_shutdown(cancel: CancellationToken) {
    tokio::spawn(async move {
        #[cfg(unix)]
        let result = async {
            let mut terminate =
                tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
            tokio::select! {
                result = tokio::signal::ctrl_c() => result,
                _ = terminate.recv() => Ok::<(), std::io::Error>(()),
            }
        }
        .await;
        #[cfg(not(unix))]
        let result = tokio::signal::ctrl_c().await;
        if let Err(error) = result {
            tracing::error!(%error, "failed to listen for shutdown");
            return;
        }
        info!("shutdown requested");
        cancel.cancel();
    });
}
