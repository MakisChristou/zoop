# Zoop API

**Keep the recordings. Improve the analysis. Own the history.**

Zoop API is the self-hosted backend for [Zoop for iPhone](../docs/IPHONE_SETUP.md)
and [Zoop web](../web/README.md). It stores raw WHOOP 5.0 / MG
recordings in PostgreSQL and turns them into sleep, activity, weight and health trends.
Both clients read the same results.

[iPhone](../docs/IPHONE_SETUP.md) ·
[API](README.md) ·
[Web dashboard](../web/README.md)

## What it does

- Accepts retry-safe uploads and retains the original sensor frames.
- Decodes recordings and analyses sleep, workouts, steps and nightly physiology.
- Tracks weight goals, weekly pace and past cut, bulk and maintenance phases.
- Reprocesses history with versioned algorithms while preserving manual corrections.
- Keeps accounts and devices private, with operational statistics for administrators.
- Shares selected metrics through revocable, optionally password-protected dashboards.

**Rust + PostgreSQL.** No Redis or object storage. The iPhone owns the Bluetooth
connection; the server handles storage and analysis. Profile photos are small,
private JPEGs stored in PostgreSQL too.

**Developer preview.** Zoop is actively developed and has not had an independent
security audit. Its health estimates are not clinically validated. It is not
affiliated with WHOOP and does not reproduce WHOOP's proprietary scores.

## Run locally

Install the Rust version pinned in `rust-toolchain.toml`, Docker and `just`.
From the repository root:

```sh
cd server
just up
just run
```

`just up` starts the development PostgreSQL container and applies migrations.
The database uses port **5433** and the API uses **8471**. Check it with
`curl http://127.0.0.1:8471/health`. `just down` stops the database without deleting
its volume. The example credentials are for development only.

## Self-hosting

Use the root [Docker Compose installation](../docs/SELF_HOSTING.md) for the full
stack. This directory's `docker-compose.yml` starts only a development database.

For the current manual setup, build the Rust binary, provide PostgreSQL and a TOML
configuration, then follow the [operations reference](docs/OPERATIONS.md) and
[account guide](docs/private-web.md). Account creation and password recovery
currently use the operator CLI.

Network access is the operator's choice. Zoop does not provision a public hostname,
reverse proxy, certificates or a VPN. Serve the web app and `/v1/` on the same
origin, keep PostgreSQL private, and configure the exact browser origin.
The current iPhone app requires HTTPS except for loopback development URLs.

Back up PostgreSQL and test a restore. Original recordings cannot be recovered
by rerunning analysis if the database's only copy is lost.

## Develop

```sh
just ci
ZOOP_TEST_DATABASE_URL=postgres://zoop:zoop@localhost:5433/zoop just test-db
```

`just ci` runs formatting, Clippy and unit tests. Database tests cover ownership,
corrections, recovery and sync in isolated schemas. Use a disposable development
database for them.

- [Architecture](docs/ARCHITECTURE.md) · [Strap protocol](docs/PROTOCOL.md)
- [Operations and endpoints](docs/OPERATIONS.md) · [Accounts](docs/private-web.md)
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

[MIT license](LICENSE).

Recovery uses a documented [server-side method](docs/recovery.md), shared by iPhone and web.

Shared dashboards expose only the measurements their owner selects. See the
[sharing contract](docs/sharing.md) for access rules and deployment checks.
