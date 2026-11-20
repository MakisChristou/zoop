# Zoop API

**Keep the recordings. Improve the analysis. Own the history.**

Zoop API is the self-hosted backend for [Zoop for iPhone](https://github.com/MakisChristou/zoop)
and [Zoop web](https://github.com/MakisChristou/zoop-web). It stores raw WHOOP 5.0 / MG
recordings in PostgreSQL and turns them into sleep, activity, weight and health trends.
Both clients read the same results.

[iPhone](https://github.com/MakisChristou/zoop) ·
[API](https://github.com/MakisChristou/zoop-api) ·
[Web dashboard](https://github.com/MakisChristou/zoop-web)

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

The [Nix](https://nixos.org/download/) development shell supplies Rust, PostgreSQL
and `just`:

```sh
git clone https://github.com/MakisChristou/zoop-api.git
cd zoop-api
nix develop
just pg-start
just run
```

In another terminal:

```sh
curl http://127.0.0.1:8471/health
```

The development database runs on port **5433** and the API on **8471**.
`just pg-stop` stops the database without deleting it. The example credentials
are for local development only. Docker Compose supplies an alternative development
database, not a complete production installation.

## Self-host

The flake provides a server package and a [NixOS module](nix/module.nix).
For other hosts, build the Rust binary and provide a PostgreSQL database and TOML
configuration; see the [operations reference](docs/OPERATIONS.md).

Before connecting the apps:

1. Set up HTTPS, keep PostgreSQL private and bind the API behind your reverse proxy.
2. Apply migrations and follow the [account setup guide](docs/private-web.md) to
   create an administrator, assign devices and enable private accounts.
3. Connect the iPhone and [web dashboard](https://github.com/MakisChristou/zoop-web)
   to that server.

Accounts and password recovery are managed through the operator CLI. There is no
public registration or hosted Zoop service. Admin statistics do not grant access
to other users' health records.

Back up PostgreSQL and test a restore. Raw recordings are the source of truth;
derived results can be rebuilt, but your only copy of the original data cannot.

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
