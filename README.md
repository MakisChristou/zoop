# snoop-api

## Profile measurements and photos

Profile weight follows the most recent non-removed measurement by local date,
preferring Apple Health within that date. Historical imports cannot roll current
weight backward. A manual profile weight is only the fallback before any measurement.
Profile responses include `weight_measured_at`, `weight_source` and
`weight_source_name`; older clients can ignore these fields. Historical analytics
resolve the most recent measurement before that day's end, never a future weight.
Weight edits and removals requeue affected workout days through the existing worker.

Authenticated `GET`, `PUT` and `DELETE /v1/devices/{deviceId}/profile/photo` read,
replace or remove one private photo. PUT accepts `image/jpeg`, at most 256 KiB and
512 pixels per dimension. The API decodes with bounded resources and re-encodes to
strip metadata. GET/PUT return the normalized JPEG; absent photos return 404 and
DELETE is idempotent (204). Images are stored as Postgres `BYTEA`; no object storage
or public image URLs are used. Apply migrations 0012 and 0013 before starting this
version. Profile photo tests and measured-weight regressions run in `just test-db`.

**Your WHOOP data, on your own server.**

snoop-api is a self-hosted backend for WHOOP 5.0 and WHOOP MG straps. A companion
iPhone app ([snoop](https://github.com/MakisChristou/snoop)) talks to the strap over
Bluetooth and uploads the raw sensor frames; this service stores them, decodes them, and
computes sleep and recovery metrics from published methods. No WHOOP account, no WHOOP
cloud, no subscription.

Written in Rust. Postgres is the only dependency.

> **Status: early development.** Ingest, decoding, nightly sleep windows, physiology
> and a first four-class staging run end to end on real strap data. Nothing is
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
- **Nightly sleep analysis**: sleep windows anchored on the strap's own rest flag with
  heart-rate confirmation; time in bed, asleep, awakenings, efficiency; resting HR,
  HRV, breathing rate, skin temperature and SpO₂; a first four-class staging
  (wake / light / deep / REM) from motion, heart rate, HRV and breathing, with the
  published accuracy limits of wrist devices stated plainly.
- **HRV primitives** (RMSSD, SDNN, ln-RMSSD) and winsorised rolling baselines.

## Quick start

Requirements: Rust 1.97+, Postgres 18, [`just`](https://just.systems). The `flake.nix`
provides all of them (`nix develop`, or `direnv allow`), and also packages the service
for NixOS (see Deploying).

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
migrations; `snoop run` starts the service; `snoop analyze --device <serial> --night
YYYY-MM-DD` scores one night and prints the result.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | liveness |
| `POST` | `/v1/ingest` | legacy batches; returns non-2xx if any frame cannot be acknowledged |
| `POST` | `/v2/ingest` | per-frame receipts; UUID identities and isolated legacy sequences |
| `GET` | `/ready` | worker readiness; 503 for stale, failed or paused workers |
| `GET` | `/v1/devices/{deviceId}/processing` | pending decode, analysis, failures and oldest pending date |
| `GET` | `/v1/devices/{deviceId}/latest` | most recent decoded sample |
| `GET` | `/v1/devices/{deviceId}/days/{date}` | minute-averaged samples for a UTC day |
| `GET` | `/v1/devices/{deviceId}/sleeps?limit=14` | analysed nights with stage segments, newest first |
| `GET` | `/v1/devices/{deviceId}/days?limit=14&tz=UTC` | daily summaries with steps, heart rate, day load and zones |
| `GET` | `/v1/devices/{deviceId}/days/{date}/steps?tz=UTC` | steps per local hour and walking bouts |
| `GET` | `/v1/devices/{deviceId}/workouts?limit=30` | detected sessions, newest first, with the user's label applied |
| `PUT` | `/v1/devices/{deviceId}/workouts/{id}/kind` | relabel a session: `{"kind": "walk" \| "resistance" \| "activity"}` |
| `GET` `PUT` | `/v1/devices/{deviceId}/profile` | body profile (sex, birth year, weight, height) and home time zone |

All `/v1` and `/v2` routes require `Authorization: Bearer <server.ingest_token>`.

## Repository layout

```
crates/
  snoop-proto      protocol: framing, records, events, commands
  snoop-analytics  HRV, baselines; sleep staging in progress
  snoop-config     TOML configuration and validation
  snoop-storage    Postgres via sqlx
  snoop-core       transactional decoder and durable history worker
  snoop-api        axum HTTP API
  snoop            binary: run | migrate | validate
migrations/        schema, applied by `snoop migrate`
docs/              architecture, protocol notes, roadmap
```

## Deploying on NixOS

The flake exports a package and a NixOS module. In your system flake:

```nix
{
  inputs.snoop-api.url = "github:MakisChristou/snoop-api";

  outputs = { nixpkgs, snoop-api, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        snoop-api.nixosModules.default
        {
          services.snoop = {
            enable = true;
            port = 8471;
            tokenFile = "/run/secrets/snoop-token";  # the bearer token, nothing else
            openFirewall = true;
          };
        }
      ];
    };
  };
}
```

The module provisions a local Postgres database and role, runs migrations before
start, reads the token through a systemd credential so it never enters the Nix store,
and restarts the service on failure. Put a reverse proxy or a private overlay network
in front of it if the host is reachable from outside your LAN.

`nix build .#snoop` builds the binary on its own.

## Development

Database-backed store tests run only when `SNOOP_TEST_DATABASE_URL` points at a migrated
development database, for example `SNOOP_TEST_DATABASE_URL=postgres://snoop:snoop@localhost:5433/snoop cargo test -p snoop-storage`;
`just ci` needs no database.

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

### Reliable history and database tests

The durable history worker replaces the trailing-day loops. It seeds all stored
sample dates once per device, profile time zone and algorithm-version pair, then
processes coalesced jobs invalidated by later data. No date range or cursor can
silently skip an old upload. `worker.history_enabled = false` pauses analysis while
intake and decoding continue; the same option is `services.snoop.historyEnabled`
in NixOS. The reconciliation interval remains `worker.analysis_interval_s`.

Sleep and workout/day load have independent versions. Their
physiological inputs are now bounded by the day being calculated. Profile revisions
are retained; existing historical profiles have only a bootstrap snapshot, not
invented past measurements. Previous workout results remain readable until each
replacement day is published, including an explicitly completed empty day.

The CLI `analyze` and `analyze-workouts` commands enqueue durable work and print a
preview. Publication happens through the supervised worker, so the CLI cannot race
it or bypass the generation check. Backfill work never creates eligible session
notifications. A job failure retains the last result and retries with capped backoff.

Run the database recovery suite explicitly against a **development** database:

```sh
export SNOOP_TEST_DATABASE_URL=postgres://snoop:snoop@localhost:5433/snoop
just test-db
```

These tests create isolated schemas, apply the real migrations and require a working
connection. They cover upload conflicts, lost-response retries, legacy compatibility,
transaction rollback, replay, leases, stale-worker fencing, late historical samples,
atomic publication, empty results, labels, profile history, DST and quarter-hour
zones. CI runs them with Postgres; the ordinary unit suite remains database-free.
See [the rollout and recovery guide](docs/RELIABLE_HISTORY.md) for deployment order.

## Workout corrections

Workout reads expose stable effective sessions. Reversible corrections preserve user
choices through late uploads and algorithm upgrades; interval metrics are recalculated
from raw-derived samples. See [the correction contract](docs/WORKOUT_CORRECTIONS.md).
The database-backed suite includes correction operations and worker races (`just test-db`).

## Sleep corrections and reset

Sleep supports stable main-sleep and nap records, time/type edits, additions, merges,
removal/restoration, and undo. Full-day analysis and coverage-aware staging use sleep
version 4; downstream workout/day Load uses version 4. Existing nights remain visible
through backfill. [Sleep and reset contract](docs/SLEEP_CORRECTIONS.md) documents the
routes, saved time-zone semantics, missing-data reporting, and reversible resets for
sleep, workouts, date ranges, or all recorded history.

## Apple Health export and weight history

Migration 0009 adds per-device opaque Health namespaces, independent export versions,
immutable export changes, step bootstrap receipts and source-preserving weight
measurements. Session projections publish in their existing transactions, including
removals and metric-only recalculation. Sleep intervals use the same known one-second
sleep flag accounting as the app totals; wake/unknown gaps remain gaps. Current sleep
waits for sustained awake evidence (or confirmed edited bounds) before export. Day
publication refreshes UTC-minute steps using the existing walking/running filter.
No raw rows are changed and no analytics version bump is required.

Authenticated endpoints:

- `GET /v1/devices/{deviceId}/health`: namespace, committed cursor, earliest data and
  a recently confirmed automatic main-sleep wake for optional weight reminders.
  Confirmation requires settled sleep analysis, at least 25 awake minutes in the
  first 30 minutes after waking, and a complete recent awake window (at least 240
  samples in the newest five minutes, none asleep). That window may be up to
  15 minutes behind wall-clock time to accommodate batched uploads; stale or
  sparse data cannot qualify. The app still suppresses reminders after a weigh-in.
- `GET /v1/devices/{deviceId}/health/exports?cursor=0&snapshot=true`: latest export
  per identity at a captured watermark. Continue using `next_cursor` and `watermark`.
  Once done, use `snapshot=false` after that watermark for changes. Pages are bounded;
  retained tombstones, not missing list entries, indicate removal.
- `POST /v1/devices/{deviceId}/health/prepare` with `from`/`to` dates: initializes
  at most three UTC days of step history per call, clamped to existing samples.
- `GET /v1/devices/{deviceId}/weights?from=...&to=...&after=...`: measurements,
  including tombstones; pages contain at most 250 rows ordered by opaque ID.
- `PUT /v1/devices/{deviceId}/weights`: value, measured date, stable ID, source,
  source name and expected version. Identical retries are idempotent. Conflicting
  edits return 409; invalid measurements return 400.
- `POST /v1/devices/{deviceId}/weights/remove-imports` with `ids`: applies explicit
  Health deletion IDs only to imported mirrors. It cannot remove Snoop weigh-ins.

All routes use the existing installation bearer-token boundary and device scope.
The iPhone owns Health permission and source checks. Imported weight is stored only
following the user's connection/backfill consent. Other Health types are not imported.
Weight history does not mutate the analytics body profile. The server never writes
into Health directly and never imports a Health-derived aggregate as raw strap data.

A dataset row serializes export counter allocation until transaction commit; consumers
cannot miss a lower sequence committed after a later one. Snapshot pages use immutable
changes at the captured watermark, so concurrent publication cannot move a row between
pages. Payload equality avoids no-op version churn. Back up the Health tables with the
rest of the database. The app rejects cursor rollback or newer Health sample versions;
do not reset counters or reuse namespaces after an incompatible database restore.

Run `just ci`, then `just test-db` with an explicit development database URL. The
Health suite covers sleep gaps, pending metrics, removal/undo, concurrent publication,
step correction, weight retries/source boundaries and recent-awake reminder gating.
Physical Health permission, syncing, and notification delivery require separate iPhone
acceptance; simulator and database tests cannot prove those behaviors.

### Read performance and incremental weights

Migrations 0010 and 0011 add rebuildable daily summaries and a per-device weight
change cursor. They preserve raw samples, analysis versions, correction identities,
Health export ownership and the existing endpoint formats. Deploy the matching
server binary and run `snoop migrate` before restarting it. Migration 0010 scans
existing sample timestamps once to build day markers; allow for that initial cost
on a large history. A warm day read uses cached aggregates. A dirty/missing day
reads only that local day and its predecessor sample, preserving counter behavior.

Sample writes invalidate affected local-day projections and the next counter's
day, even across a recording gap. A per-device transaction advisory lock fences
first cache creation against concurrent writes. A competing reader computes an
uncached snapshot instead of waiting. Cold cache publication can briefly delay
sample decoding; raw-frame ingestion is unaffected. The history worker warms the
projection on normal analysis passes. Nothing advances an analysis version here.

`GET /v1/devices/{device}/sleeps?summary=true` omits the stage trace while retaining
all summary measurements and version selection. The default response is unchanged.
`GET /v1/devices/{device}/weight-changes?cursor=0&limit=250` returns rows,
next_cursor, watermark and done. Continue with the returned watermark until done,
then begin the next pass at next_cursor. Merge by identity/version and retain
removal tombstones; absence is not deletion. The cursor is transaction-ordered per
device and survives idempotent retries and updates during pagination.

`just test-db` now includes projection equivalence (the original query is the
reference), DST, sample replay/deletion, concurrent cache filling and weight
cursor upgrades. It requires an explicitly supplied development database and
creates fresh schemas. `tools/performance-fixture.sql` is a synthetic-only fixture
for a fresh development database: 1,022,000 samples, 365 nights and 730 weigh-ins.
Keep history analysis disabled while comparing UI screenshots from that fixture.
