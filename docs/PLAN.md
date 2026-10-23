# snoop — plan

Self-hosted, Rust-first replacement for the WHOOP cloud, for one WHOOP MG.
iOS app holds the Bluetooth bond and uploads raw frames; a home server (Mac mini,
reached over Tailscale) decodes, analyses and serves a SvelteKit dashboard.

## Decisions (2026-10-22)

| Topic | Decision |
|---|---|
| Strap | WHOOP MG (ECG path in scope) |
| iOS signing | Paid Apple Developer account, TestFlight |
| Hosting | Home server / Mac mini, Docker Compose, Tailscale for TLS and access |
| Backend | Pure Rust: axum + sqlx, plain Postgres 18 |
| Frontend | SvelteKit (TypeScript); home not yet decided, kept out of this repo |
| Protocol core | `poop` crate (eugenehp/whoop-rs, Apache-2.0) behind `snoop-proto` |
| Code style | see AGENTS.md |
| Commits | Conventional Commits, developer's default git identity |
| Test vectors | LeonardSEO/wearable5.0 `golden.json` (MIT) |
| Reference only, no code copied | NOOP (PolyForm NC), OpenStrap (AGPL), Goose (UNLICENSED) |

## Repos

- `snoop-api` (this repo): pure Rust + Postgres backend.
- `snoop` (github.com/MakisChristou/snoop): the iPhone app. Depends on `crates/snoop-ffi` from this repo via a pinned Cargo git dependency and builds it into an xcframework.
- Web dashboard: location undecided (own repo `snoop-web`, or static files served by `snoop-api`). The SvelteKit draft is parked outside the repo.

## Layout

```
crates/snoop-proto      frame verify + decode facade, CLIENT_HELLO, history ACK
crates/snoop-analytics  HRV, baselines; later sleep, strain, recovery
crates/snoop-config     TOML config + validation
crates/snoop-storage    Postgres (sqlx): raw_frames is the source of truth
crates/snoop-core       decode worker, proto-versioned backfill
crates/snoop-api        axum API
crates/snoop-ffi        UniFFI surface -> Swift xcframework (consumed by the snoop repo)
crates/snoop            binary: run / migrate / validate
migrations/             sqlx migrations
docker-compose.yml      local Postgres
captures/               PacketLogger / btsnoop captures (gitignored)
refs/                   cloned reference repos (gitignored)
```

## Key protocol facts (WHOOP 5/MG, service fd4b0001)

- Envelope: `AA 01 [len u16] [dst] [src] [crc16-modbus of 0..6] inner... [crc32]`, inner zero-padded to 4.
- Inner: `[type][seq][cmd][b3][payload]`. type 0x23 = command. b3 is per-command (0x01 for HELLO/NAME/SET_CONFIG, 0x00 for GET_DATA_RANGE/SEND_HISTORICAL).
- Records (types 43/47): layout byte at frame[9]; R18 biometric, R20 optical, R21 IMU, R22 v9, R26 compact optical, R16/R17 MG ECG.
- History offload stalls after one chunk unless the 8-byte cursor at inner offset 13 of progress frames is echoed back as command 0x17.
- The strap bonds to one device. On iPhone, an app can ride the OS bond the official app created, but only one app can hold the connection at a time. macOS cannot initiate the authenticated pairing at all.
- Standard HR (0x2A37) streams without a bond.
- R-R intervals are milliseconds (not 1/1024 s).
- MG detection: DIS model `MG`, serial prefix `5AM`.

## Milestones

1. **Workspace builds, golden vectors pass** — done 2026-10-22; restructured into snoop-api 2026-10-23.
2. **Local stack up**: compose on this Mac, migrations applied, `POST /v1/ingest` accepts a golden frame, worker writes a `samples` row.
3. **iOS spike**: app subscribes to fd4b channels on the bonded iPhone, writes CLIENT_HELLO, streams packet 40 live HR, logs every frame, uploads batches.
4. **History offload**: GET_DATA_RANGE, SEND_HISTORICAL, ACK loop, background BLE, idempotent upload. R18 lands in `samples`.
5. **Dashboard v1**: live HR, day view, skin temp, steps, battery.
6. **Analytics v1**: nightly RHR, RMSSD, respiratory rate; then sleep detection/staging from R18+R21; then recovery and strain with baselines.
7. **MG ECG**: R16/R17 strips viewer; lead-off handling.
8. **Parity push**: workouts, stress, journal, HealthKit export, AI coach (BYO key).

## Before unpairing from the official app

- Export all WHOOP data (app → Settings → Export) and keep it in `captures/official-export/`.
- Record an iOS PacketLogger capture of one overnight sync (Bluetooth logging profile from developer.apple.com/bug-reporting/profiles, then sysdiagnose). This is ground truth for the ACK loop and the record mix.
