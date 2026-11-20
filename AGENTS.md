# AGENTS.md

Conventions for contributors and coding agents working in zoop-api. Read before
changing anything.

## What this is

A self-hosted backend for WHOOP 5.0 / MG straps. The companion iOS app holds the
Bluetooth connection and uploads raw frames; this service stores, decodes and analyses
them. The primary goal is sleep tracking that matches the official app; strain,
recovery and the rest follow.

## Hard rules

- **Greenfield, independently implemented.** Other projects (NOOP, OpenStrap,
  wearable5.0, whoop-rs, Goose, Gadgetbridge forks) are *reference material only*. Read
  them to understand the protocol or an algorithm, then write our own implementation.
  Never add one of them as a dependency, vendor their code, or copy their test fixtures.
  A local `refs/` directory for reading them is gitignored.
- **Pure Rust + Postgres.** No other languages or datastores. Postgres through `sqlx`
  runtime queries and embedded `migrate!`. No ORM, no Redis, no extensions.
- **Raw frames are the source of truth.** Never delete or rewrite `raw_frames`. Derived
  tables are rebuilt from them: bump `zoop_proto::PROTO_VERSION` or
  `zoop_analytics::ALGO_VERSION` instead of editing rows in place.
- **Published methods only.** Analytics implement cited, peer-reviewed methods. Each
  module's doc comment names the paper. No WHOOP formulas are reproduced.
- **Public project.** No personal names, host names, network details or credentials in
  code, docs, examples or commit messages. Everything deployment-specific is
  configuration.
- **Conventional Commits**: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `build`,
  `ci`, with the crate name (minus prefix) as optional scope: `feat(proto): …`.
  Imperative mood, lower case, no trailing period. Never override the git identity.

## Code style

- Edition 2024, `resolver = "3"`, dependencies declared once in
  `[workspace.dependencies]`, `[lints] workspace = true` in every crate.
- `cargo fmt --all` before every commit; clippy must pass with `-D warnings`;
  `unsafe_code = "deny"`; every public type derives `Debug`.
- One crate per concern under `crates/`. Add a crate rather than bloating one.
- `lib.rs` declares private modules and re-exports the public surface; no logic.
- Errors: per-crate `thiserror` enum and `XxxResult<T>` alias in `error.rs`. Storage
  errors name the `StoreOperation` that failed. The binary alone uses `anyhow` with
  `.context(…)`. No `unwrap`/`expect` outside tests.
- Tests in a sibling `tests.rs` or the crate's `tests/` directory. Protocol decoders are
  tested against frames built by our own encoder; real captures become fixtures only
  when they come from our own hardware.
- Doc comments on every public item, `# Errors` on fallible functions, module-level
  `//!` explaining why the module exists. Named constants over magic numbers.
- Configuration is TOML via `figment`; secrets are `secrecy::SecretString`; `ZOOP_*`
  env vars override keys. `zoop validate` must pass before `zoop run` proceeds.
- Long-running tasks take a `CancellationToken` and shut down cleanly.

## Workflow

```sh
nix develop        # or direnv allow; provides rust, postgres, just
just pg-start      # repo-local Postgres + migrations (or `just up` for Docker)
just run           # API + decode worker using zoop.dev.toml
just ci            # fmt-check, clippy -D warnings, tests — before every commit
```

CI runs the same three jobs. Do not merge red. The service is config-file driven so it
can be packaged as a systemd or NixOS service without code changes.

## Protocol facts that bite

See `docs/PROTOCOL.md`. The short list:

- R-R intervals are **milliseconds** on the wire, not 1/1024 s ticks.
- The history offload stalls after one chunk unless the 8-byte HISTORY_END token is
  echoed back in a HISTORICAL_DATA_RESULT command.
- The first argument byte after the command code differs per command; a wrong value is
  silently ignored by the strap.
- The strap keeps one encrypted bond. On iOS an app rides the bond the official app
  created; macOS cannot bond with the strap at all.

## When unsure

`docs/ARCHITECTURE.md` and `docs/ROADMAP.md` record decisions already made. Propose
changes in a `docs:` commit rather than drifting from them silently.

## Metric parity

- **iPhone and web must display the same backend-owned metrics.** Use the same metric definition, source field, day/timezone and goal scope. Clients may format values, convert display units and render goal progress; they must not independently derive health metrics or substitute a different raw/filtered value. Missing data stays missing. Refresh timing may differ, but equal backend snapshots must produce equal readings.
- Displayed steps use backend walking/running-filtered counts (`steps_walking` in daily summaries, `walking` in hourly steps), never the raw strap counter. Cover source selection with regression tests when changing metric presentation.
