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

1. The phone persists complete frames in receive order before acting on history-end
   markers. New frames carry UUID upload identities; queued pre-upgrade frames retain
   their legacy sequence identities. `/v2/ingest` returns a receipt for each frame.
   Stored and duplicate receipts require equal bytes/channel; conflicts and rejected
   frames remain on the phone. V1 returns non-2xx for a partial batch.
2. The decoder reads pending protocol revisions. A single transaction writes or
   replaces decoded rows, marks the frame, and invalidates dependent analysis dates.
   CRC-valid unfamiliar payloads remain raw. Semantic failures are recorded separately
   so one malformed frame does not block healthy records.
3. `HistoryWorker` bootstraps stored sample dates and consumes durable Postgres jobs.
   Sleep and workout/day-load versions are independent. Leases exclude competing
   workers; generations fence changed inputs. Sessions, day load and completion
   publish in one transaction, so readers retain the previous completed version
   until the replacement is ready. Empty completion is meaningful, not missing work.
4. A sample invalidates its fixed-window sleep night, its local day and adjacent
   context days, plus existing days whose trailing observed-HR inputs can include it.
   A changed sleep invalidates downstream resting-HR and sleep-exclusion consumers.
   Workout jobs wait for pending prerequisite nights. Retries survive restarts.
5. Profile snapshots are time-aware and labels are independent overlap-based user
   corrections. Historical HR maximum and resting HR use an as-of-day cutoff. Initial
   profile history is an explicit bootstrap assumption because older edits were not
   recorded. Job provenance stores versions, profile, physiology and parameters.
6. The service supervises worker tasks. `/health` is liveness; `/ready` checks worker
   freshness and pause state. Authenticated processing status reports decode and
   analysis lag separately. A recent sample alone never proves history is complete.

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
- `profiles`, `profile_revisions`, `workout_labels` — current profile, historical snapshots and independent corrections.
- `analysis_jobs`, `analysis_bootstraps`, `worker_status` — durable progress, completion provenance and worker health.

## Deployment

The binary is configuration-file driven and has no runtime dependencies beyond Postgres,
so it packages as a plain systemd unit, a container (`crates/snoop/Dockerfile`), or a
NixOS service module. TLS and network exposure are left to the host (reverse proxy or
a private overlay network).
