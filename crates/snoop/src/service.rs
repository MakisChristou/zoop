use std::time::Duration;

use anyhow::Context;
use secrecy::ExposeSecret;
use snoop_api::AppState;
use snoop_config::Config;
use snoop_core::{Decoder, NightAnalyzer};
use snoop_storage::PostgresStore;
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;
use tracing::info;

use crate::commands;

pub(crate) async fn run(config: Config) -> anyhow::Result<()> {
    commands::validate(&config).context("configuration invalid")?;

    let cancel = CancellationToken::new();
    spawn_shutdown(cancel.clone());

    let store = PostgresStore::connect(config.storage_config.postgres_url.expose_secret())
        .await
        .context("connecting to Postgres")?;
    store.ping().await.context("pinging Postgres")?;

    let decoder = Decoder::new(
        store.clone(),
        config.worker_config.batch_size,
        Duration::from_millis(config.worker_config.poll_interval_ms),
    );
    let worker = tokio::spawn(decoder.run(cancel.clone()));
    let analyzer = NightAnalyzer::new(
        store.clone(),
        Duration::from_secs(config.worker_config.analysis_interval_s),
    );
    let analysis = tokio::spawn(analyzer.run(cancel.clone()));

    let app = snoop_api::build_router(AppState::new(
        store,
        config.server_config.ingest_token.clone(),
    ));
    let listener = TcpListener::bind(&config.server_config.bind)
        .await
        .with_context(|| format!("binding {}", config.server_config.bind))?;
    info!(bind = %config.server_config.bind, "API listening");

    let server_cancel = cancel.clone();
    axum::serve(listener, app)
        .with_graceful_shutdown(async move { server_cancel.cancelled().await })
        .await
        .context("serving API")?;

    cancel.cancel();
    worker.await.context("joining decode worker")??;
    analysis.await.context("joining night analyzer")??;
    info!("snoop stopped");
    Ok(())
}

fn spawn_shutdown(cancel: CancellationToken) {
    tokio::spawn(async move {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(%error, "failed to listen for ctrl-c");
            return;
        }
        info!("shutdown requested");
        cancel.cancel();
    });
}
