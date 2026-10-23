# snoop-api

**Your WHOOP data, on your own server.**

snoop-api is a self-hosted backend for WHOOP 5.0 and WHOOP MG straps. A companion
iPhone app ([snoop](https://github.com/MakisChristou/snoop)) talks to the strap over
Bluetooth and uploads the raw sensor frames; this service stores them, decodes them, and
computes sleep and recovery metrics from published methods. No WHOOP account, no WHOOP
cloud, no subscription.

Written in Rust. Postgres is the only dependency.

> **Status: early development.** Ingest, storage and R18 biometric decoding work end to
> end against synthetic frames. Sleep analysis is the current focus. Nothing here is
> validated against the official app yet. See [docs/ROADMAP.md](docs/ROADMAP.md).

## How it works

```
 WHOOP strap ──BLE──▶ snoop (iOS) ──HTTPS──▶ snoop-api ──▶ Postgres
                      holds the bond,        verifies CRCs,     raw_frames (source of truth)
                      reassembles frames,    stores raw bytes,  samples, events, ecg_strips
                      uploads in batches     decodes, analyses  sleeps, recoveries, strains
```

Raw frames are never modified or deleted. Every decoded or derived row carries the
protocol or algorithm version that produced it, so history can be recomputed whenever
the decoders or the analytics improve.

## Features

- **Format-1 protocol implementation** for WHOOP 5.0 / MG: framing, CRC-16/MODBUS and
  CRC-32 validation, BLE reassembly, command building (hello, data range, history
  offload and its acknowledgement loop).
- **Record decoding**: R18 one-second biometric summary (heart rate, R-R intervals,
  motion, skin temperature, steps, the strap's own sleep/wake flag, SpO₂ windows),
  MG ECG strips (R16/R17), events, offload metadata and command responses.
- **Idempotent ingest API** protected by a bearer token; duplicates from retries are
  counted, not stored twice.
- **Decode worker** with versioned backfill.
- **HRV primitives** (RMSSD, SDNN, ln-RMSSD) and winsorised rolling baselines.

## Quick start

Requirements: Rust 1.97+, Postgres 18, [`just`](https://just.systems). A `flake.nix`
provides all of them (`nix develop`, or `direnv allow`).

```sh
cp snoop.dev.toml snoop.toml      # then set server.ingest_token
just pg-start                     # repo-local Postgres on :5433 and migrations
                                  # (or `just up` to use Docker instead)
just run                          # API + decode worker
curl localhost:8471/health
```

Point the snoop iOS app at `http://<host>:8471` with the same token.

## Configuration

Configuration is a TOML file (`--config`, default `snoop.toml`). Any key can be
overridden with an environment variable: `SNOOP_SERVER__INGEST_TOKEN`,
`SNOOP_STORAGE__POSTGRES_URL`, and so on.

```toml
[server]
bind = "0.0.0.0:8471"
ingest_token = "<openssl rand -hex 32>"

[storage]
postgres_url = "postgres://snoop:snoop@localhost:5433/snoop"

[worker]
poll_interval_ms = 5000
batch_size = 500
```

`snoop validate --config snoop.toml` checks the file; `snoop migrate` applies schema
migrations; `snoop run` starts the service.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | liveness |
| `POST` | `/v1/ingest` | batch of base64 frames; idempotent on `(device_id, client_seq)` |
| `GET` | `/v1/devices/{deviceId}/latest` | most recent decoded sample |
| `GET` | `/v1/devices/{deviceId}/days/{date}` | minute-averaged samples for a UTC day |

All `/v1` routes require `Authorization: Bearer <server.ingest_token>`.

## Repository layout

```
crates/
  snoop-proto      protocol: framing, records, events, commands
  snoop-analytics  HRV, baselines; sleep staging in progress
  snoop-config     TOML configuration and validation
  snoop-storage    Postgres via sqlx
  snoop-core       decode worker and future analytics workers
  snoop-api        axum HTTP API
  snoop            binary: run | migrate | validate
migrations/        schema, applied by `snoop migrate`
docs/              architecture, protocol notes, roadmap
```

## Development

```sh
just ci            # fmt-check, clippy -D warnings, tests
```

Conventions for contributors and coding agents are in [AGENTS.md](AGENTS.md).

## Acknowledgements

The wire protocol was understood by reading public interoperability research, in
particular the documentation published by the NOOP, wearable5.0, Goose, whoop-rs and
OpenStrap projects. snoop-api contains no code from any of them; every line here is an
independent implementation.

## License

MIT. snoop-api is an independent project, not affiliated with or endorsed by WHOOP, Inc.
Metrics are approximations from published methods and are not medical advice.
