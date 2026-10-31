# Architecture

## Components

| Component | Responsibility |
|---|---|
| iOS app ([snoop](https://github.com/MakisChristou/snoop)) | Holds the Bluetooth connection, reassembles frames, drives the history offload, queues and uploads raw frames. Implements the protocol independently in Swift. |
| `snoop-api` | Verifies and stores raw frames, decodes them, computes metrics, serves read endpoints. |
| Postgres | The only datastore. |

The phone is deliberately thin: everything that can be recomputed lives on the server,
where it can be re-run over the full history.

## Data flow

1. The app uploads batches of CRC-valid frames to `POST /v1/ingest`, each with a
   monotonic per-device `client_seq`. The server re-verifies every frame and inserts it
   into `raw_frames`; `(device_id, client_seq)` is unique, so retries are harmless.
2. The decode worker (`snoop-core::Decoder`) picks frames whose `decoded_proto` is
   missing or older than `snoop_proto::PROTO_VERSION` and writes `samples`, `events` and
   `ecg_strips`. Re-decoding upserts, so a protocol fix is a version bump plus time.
3. Analytics workers read `samples` and write `sleeps`, `workouts` and `strains`, keyed
   by `algo_version`. Old and new numbers coexist until the old version is dropped. The
   night analyzer re-runs the trailing three nights; the workout analyzer the trailing
   two local days of each device's profile time zone.
4. User input the analytics read, `profiles` and `workout_labels`, is unversioned and
   never recomputed. Labels are matched to sessions by time overlap, so corrections
   survive a method change.

## Crates

```
snoop-proto      framing, CRCs, reassembly, record/event/response decoding, commands
snoop-analytics  HRV, baselines, sleep, staging, walking bouts, workouts, zones, energy
                 (`ALGO_VERSION` keys sleep rows, `WORKOUT_ALGO_VERSION` workouts and strains)
snoop-config     TOML schema, loading, validation
snoop-storage    PostgresStore and per-table stores, StorageError/StoreOperation
snoop-core       Decoder, night and workout analyzers, on-demand steps
snoop-api        axum router, bearer auth, ingest and read handlers
snoop            CLI: run | migrate | validate | analyze | analyze-workouts
```

Dependencies point downward only: `snoop` → `snoop-api`/`snoop-core` → `snoop-storage`
→ `snoop-proto`/`snoop-analytics`. The protocol and analytics crates have no I/O.

## Schema

- `devices` — one row per strap serial.
- `raw_frames` — append-only; `bytes` holds one complete frame; `decoded_proto` is the
  work-queue marker.
- `samples` — 1 Hz rows from R18: HR, R-R, skin temperature, steps, dynamic
  acceleration, activity class, the strap's band state (wake/still/sleep/up) and SpO₂
  when inside a measurement window.
- `events`, `ecg_strips` — as decoded.
- `sleeps`, `recoveries`, `strains`, `workouts`, `journal` — derived, versioned.
  `workouts` carries kind, load, zones, impulse, calories and steps per session;
  `strains` the same per local day.
- `profiles`, `workout_labels` — user input, unversioned; read by the analytics.

## Deployment

The binary is configuration-file driven and has no runtime dependencies beyond Postgres,
so it packages as a plain systemd unit, a container (`crates/snoop/Dockerfile`), or a
NixOS service module. TLS and network exposure are left to the host (reverse proxy or
a private overlay network).
