# AGENTS.md — snoop-api

Guidance for AI agents and humans working in this repo. Read before changing anything.

## What this is

Self-hosted backend for a WHOOP MG strap. The iOS app (`MakisChristou/snoop`) holds the
Bluetooth connection and uploads raw frames; this service stores them, decodes them and
serves read endpoints. Personal, non-commercial, privacy-first: no WHOOP account, no cloud.

## Hard rules

- **Pure Rust + Postgres.** No other languages or datastores in this repo. Postgres via
  `sqlx` (runtime queries, `query`/`query_as`, embedded `migrate!`). No ORMs, no Redis, no
  Timescale.
- **Raw frames are the source of truth.** Never delete or rewrite `raw_frames`. Derived
  tables are rebuilt from them; bump `snoop_proto::PROTO_VERSION` or
  `snoop_analytics::ALGO_VERSION` instead of mutating rows in place.
- **Conventional Commits**, always: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`,
  `test:`, `build:`, `ci:`. Optional scope is the crate name without the prefix:
  `feat(storage): ...`, `fix(proto): ...`. Imperative mood, lower case, no trailing period.
- **Use the developer's default git identity.** Never pass `-c user.name` / `-c user.email`
  or otherwise override author/committer.
- **Licensing.** Reuse only MIT / Apache-2.0 code. Reference material under `refs/`
  (gitignored) includes NOOP (PolyForm Noncommercial), OpenStrap (AGPL-3.0) and Goose
  (unlicensed): read them, never copy from them. Attribute copied test vectors in an
  `ATTRIBUTION.md` next to the fixture.
- **No WHOOP formulas.** Analytics implement published, cited methods; each module's doc
  comment names the paper.

## Code style

- Edition 2024, `resolver = "3"`, workspace-level `[workspace.dependencies]` with a short
  comment per dependency group, `[lints] workspace = true` in every crate.
- `rustfmt.toml` is law; run `cargo fmt --all`. Clippy must pass with `-D warnings`.
- `unsafe_code = "deny"`. Every public type derives `Debug`.
- One crate per concern under `crates/`: `snoop-proto`, `snoop-analytics`, `snoop-config`,
  `snoop-storage`, `snoop-core`, `snoop-api`, `snoop-ffi`, `snoop` (binary). New
  functionality goes in the crate that owns the concern; add a crate rather than bloating one.
- `lib.rs` declares private modules and re-exports the public surface with `pub use`; it
  holds no logic beyond trivial wiring.
- Errors: per-crate `thiserror` enum plus a `XxxResult<T>` alias in `error.rs`. Storage
  errors carry a `StoreOperation` naming what was being attempted. The binary uses
  `anyhow` with `.context(...)`. No `unwrap`/`expect` outside tests except on poisoned
  mutexes with a recovery path.
- Tests live in a sibling `tests.rs` (`#[cfg(test)] mod tests;`) or a `tests/` dir, not
  inline, except for very small private helpers.
- Doc comments on every public item; `# Errors` sections on fallible public functions.
  Module-level `//!` docs explain *why* the module exists.
- Named constants over magic numbers (`const RR_MAX_WORDS: usize = 4;`).
- Config is TOML loaded with `figment`; secrets are `secrecy::SecretString`; `SNOOP_*` env
  vars override keys. `snoop validate` must pass before `snoop run` starts.
- Long-running tasks take a `CancellationToken` and exit cleanly on shutdown.

## Workflow

```sh
just up          # Postgres + migrations
just run         # API + decode worker (snoop.dev.toml)
just ci          # fmt-check, clippy -D warnings, tests — run before every commit
```

CI (`.github/workflows/ci.yml`) runs the same three jobs. Do not merge red.

## Protocol facts that bite

- WHOOP 5/MG service `fd4b0001-…`; command write `…0002`, notify `…0003/4/5/7`.
- Envelope `AA 01 [len u16] [dst] [src] [crc16-modbus] inner… [crc32]`; inner
  `[type][seq][cmd][b3][payload]`, zero-padded to 4 bytes.
- History offload stalls after one chunk unless the 8-byte cursor at inner offset 13 is
  echoed back as command `0x17`.
- R-R intervals are **milliseconds** on the wire. The upstream `poop` crate converts them
  as 1/1024 s ticks; `snoop-proto` overrides that. Do not "fix" it back.
- The strap keeps one encrypted bond. On iPhone an app rides the OS bond the official app
  made; macOS cannot bond with the strap at all.

## When unsure

Check `docs/PLAN.md` for decisions already made. Don't relitigate them silently; propose a
change in a `docs:` commit or ask.
