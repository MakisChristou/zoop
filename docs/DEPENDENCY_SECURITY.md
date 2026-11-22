# Dependency security

Security checks run on pushes, pull requests and weekly. They scan Git history for
secrets, audit web/docs dependencies, validate workflow syntax and check RustSec
against the locked Rust dependencies. Jobs have read-only access and no release
credentials. Scanner findings remain visible even when a reviewed exception applies.

Run `python3 tools/test-audit-rust.py` and `python3 tools/audit-rust.py` locally
with cargo-audit 0.22.1 installed. The latter refreshes RustSec and resolves the
workspace with all configured features and target platforms.

## Reviewed exceptions

Reviewed 22 November 2026; all exceptions expire on **22 February 2027**.
The policy is executable in `tools/audit-rust.py` and covered by regression tests.
A new advisory, changed package version, expired exception or newly enabled driver
fails the check and needs another review.

| Advisory | Locked package | Reason |
| --- | --- | --- |
| RUSTSEC-2023-0071 | rsa 0.9.10 | SQLx's unused MySQL dependency; absent from the configured build graph. |
| RUSTSEC-2026-0459 | libsqlite3-sys 0.30.1 | SQLx's unused SQLite dependency; absent from the configured PostgreSQL build. |
| RUSTSEC-2026-0543 | chrono 0.4.45 | Unmaintained, used by date/time calculations. Temporary maintenance exception approved for the first release. |

The chrono exception applies only to the unmaintained warning, never to a new
vulnerability. Review a maintained replacement by **22 January 2027**, with tests
for daylight-saving transitions, local midnight, sleep dates, goal boundaries,
serialization and PostgreSQL conversions. Do not replace calendar logic without
checking historical metric parity.

The URL-parser advisory RUSTSEC-2026-0592 was addressed by updating `url` to 2.5.9.
Exceptions above are not a claim that the dependency audit is clean.
