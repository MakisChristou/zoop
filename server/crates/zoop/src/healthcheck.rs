//! Container readiness probe, without adding a shell or HTTP client to the image.
use anyhow::{Context, ensure};
use std::{net::SocketAddr, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
};

pub(crate) async fn run(config: &zoop_config::Config) -> anyhow::Result<()> {
    let mut address: SocketAddr = config
        .server_config
        .bind
        .parse()
        .context("invalid server bind address")?;
    if address.ip().is_unspecified() {
        address.set_ip(if address.is_ipv4() {
            std::net::Ipv4Addr::LOCALHOST.into()
        } else {
            std::net::Ipv6Addr::LOCALHOST.into()
        });
    }
    tokio::time::timeout(Duration::from_secs(4), async {
        let mut socket = TcpStream::connect(address).await?;
        socket
            .write_all(b"GET /ready HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            .await?;
        let mut status = [0; 12];
        socket.read_exact(&mut status).await?;
        ensure!(&status == b"HTTP/1.1 200", "API is not ready");
        Ok::<(), anyhow::Error>(())
    })
    .await
    .context("readiness probe timed out")??;
    Ok(())
}
