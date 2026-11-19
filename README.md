# Zoop API

**Your wearable history, on your server.**

Zoop API stores and analyses recordings from [Zoop for iPhone](https://github.com/MakisChristou/zoop).
The phone collects WHOOP 5.0 / MG data over Bluetooth. This Rust service keeps the
original frames in PostgreSQL and derives sleep, activity and health trends for
the phone and [web dashboard](https://github.com/MakisChristou/zoop-web).

Self-hosted developer alpha. No hosted service, medical claims or independent
security audit. Not affiliated with WHOOP. Algorithms are independently implemented;
better infrastructure does not imply clinically validated estimates.

## Run locally

With Nix installed:

```sh
git clone https://github.com/MakisChristou/zoop-api.git
cd zoop-api
nix develop
just pg-start
just run
```

The development API listens on `127.0.0.1:8471`. Its example credentials are for
loopback development only. `just pg-stop` stops the local database without deleting it.
Docker Compose is currently an alternative **development database**, not a complete
production installer.

For deployment, use the [NixOS module](nix/module.nix) and
[private-account guide](docs/private-web.md). Use HTTPS and a private database;
create accounts and assign devices before enabling private-account mode. The iPhone
requires this backend and stores credentials in Keychain. Uploads queue during outages.

## Check

```sh
just ci
ZOOP_TEST_DATABASE_URL=postgres://zoop:zoop@localhost:5433/zoop just test-db
```

Use a disposable development database: integration tests create isolated schemas.
The database suite includes account isolation, corrections, recovery and Health sync.

## Data ownership

Raw frames are retained as the source of truth. Reprocessing updates derived data;
manual corrections are preserved. Admin access exposes operational aggregates and
does not bypass per-user health-data ownership. Back up PostgreSQL and verify a
restore before trusting any installation with your only copy.

- [Architecture](docs/ARCHITECTURE.md) and [protocol](docs/PROTOCOL.md)
- [Operational and endpoint reference](docs/OPERATIONS.md)
- [Contributing](CONTRIBUTING.md) and [security](SECURITY.md)

MIT. See [LICENSE](LICENSE).
