# snoop-api

Self-hosted backend for a WHOOP MG strap. The companion iPhone app
([`snoop`](https://github.com/MakisChristou/snoop)) holds the Bluetooth connection, pulls
live and stored sensor data, and uploads raw frames here. This service stores them, decodes
them into samples, and will compute sleep, recovery and strain from published methods.

No WHOOP account, no WHOOP cloud, no subscription. Pure Rust and Postgres.

## Crates

```
crates/
  snoop-proto      # WHOOP 5/MG frame verify + decode facade over `poop`, CLIENT_HELLO, history ACK
  snoop-analytics  # HRV (RMSSD/SDNN), rolling baselines; later sleep, strain, recovery
  snoop-config     # TOML config (figment), validation
  snoop-storage    # Postgres via sqlx: raw frames (source of truth), samples, ECG strips
  snoop-core       # decode worker: pending raw frames -> samples / ECG, proto-versioned backfill
  snoop-api        # axum HTTP API: bearer-protected ingest and read endpoints
  snoop-ffi        # UniFFI surface the iOS app builds into an xcframework
  snoop            # binary: `run` (API + worker), `migrate`, `validate`
```

## Run locally

```sh
nix develop             # or `direnv allow`; provides rust, postgres, just
just pg-start           # repo-local Postgres on :5433 + migrations (`just up` for Docker instead)
just run                # API on :8080 using snoop.dev.toml
curl localhost:8080/health
```

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | liveness |
| `POST` | `/v1/ingest` | batch of base64 raw frames from the phone; idempotent on `(device_id, client_seq)` |
| `GET` | `/v1/devices/{deviceId}/latest` | most recent decoded sample |
| `GET` | `/v1/devices/{deviceId}/days/{date}` | minute-averaged samples for a UTC day |

All `/v1` routes require `Authorization: Bearer <server.ingest_token>`.

## Development

```sh
just ci     # fmt-check, clippy -D warnings, tests
```

See `AGENTS.md` for conventions and `docs/PLAN.md` for decisions and milestones.

Unofficial, independent project. Not affiliated with WHOOP, Inc. Metrics are
approximations from published methods, not medical advice.
