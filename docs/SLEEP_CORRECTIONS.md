# Sleep corrections and automatic resets

Migration 0008 adds `sleep_sessions`, `sleep_corrections`, `sleep_aliases`, and
`analysis_resets`. Sleep and workouts share the revisioned correction engine but
have separate identity and ownership namespaces. Raw frames and samples are never
changed by correction, reset, or undo.

## Reading and correcting sleep

All routes below are under `/v1/devices/{deviceId}` and require the existing bearer token.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/sleep-sessions?status=active&from=...&to=...&limit=1000` | Stable records overlapping a UTC interval; `removed` lists the archive |
| GET | `/sleep-sessions/{id}` | A current record or tombstone |
| GET | `/sleep-sessions/{id}/epochs` | Features within this record, including naps |
| POST | `/sleep-sessions/corrections` | Same idempotent command shape as workout corrections |
| POST | `/analysis/reset-preview` | Resolve a proposed reset and return its confirmation token |
| POST | `/analysis/reset` | Apply the exact reviewed reset |
| POST | `/analysis/reset-undo` | Restore manual intent before a reset |
| GET | `/analysis/resets` | Recent active resets available for undo |

Sleep correction kinds are `main` and `nap`. Bounds are half-open UTC timestamps;
the app asks for **Fell asleep** and **Woke up**. `edit`, `add`, `merge`, `remove`,
`type`, and `undo` use the shared command contract. For compatibility the receipt
uses `workout_ids` for both domains; these IDs belong to the requested namespace.
Saving requires actual sensor samples in each output interval. A stale revision,
overlap, or conflicting main sleep fails without overwriting newer work.

A record retains its saved home time zone. New records use the profile’s current
home zone. Its local wake-up date selects the day; calendar arithmetic includes
midnight and daylight-saving changes. The full wake-up day is searched, including
afternoon naps. There is one effective main sleep per date; an explicit main wins,
otherwise the longest automatic recording becomes main. Explicit naps keep their type.

Manual boundaries define the sleep period, not time in bed and not an assertion
that every second was asleep. Recorded awake breaks stay awake. Missing seconds
are reported in `unknown_s`, never counted as awake or sleep. Epochs need at least
half their seconds recorded and, unless already awake, half with heart-rate readings
before receiving a stage. Smoothing stops at gaps, and stage segments are clipped
to actual recorded spans. `unclassified_s` includes every unstaged second.
The top-level `sleep.efficiency` is null with over two minutes missing or no coverage;
legacy numeric window fields remain readable. This is a coverage/reporting change,
not a new validated sleep classifier.

Sleep version 3 and workout/day-load version 4 recompute saved history automatically.
Migration promotes existing nights/naps into stable records before backfill, so
older nights remain readable. The legacy `/sleeps` API projects effective main
sleep and naps. Changed sleep invalidates dependent workout/day Load and resting-HR
consumers. Manually fixed workouts retain their type and bounds. Recalculation
and correction results are not eligible for detection notifications.

## Reset contract

Preview accepts `{ "domains": ["sleep", "workout"], "from": "...", "to": "..." }`.
Omit both dates for all recorded history. For one recording send one domain and
`target_id`, without dates. Empty data ranges are rejected. Preview returns the
actual `from`, `to`, `manual_changes`, `expanded`, and `token`.

Connected ownership intervals expand to a fixed point, covering entire split,
merge, trim, and moved-time correction chains. Confirmation sends
`{ "operation_id": "...", "scope": { ... }, "token": "..." }`. The token fingerprints
identities and revisions, not volatile calculated metrics; changed intent requires
a fresh review (409). Retry an uncertain response with the same operation ID and
identical body. A recorded receipt is returned before rechecking the token.

Reset archives matching active commands and clears their effective overrides. It
then queues durable analysis from existing samples. Ordinary recomputation keeps
overrides; reset deliberately removes them. Superseded legacy labels do not return.
The reset snapshot preserves original IDs, ownership, and edits for undo.

Undo sends `{ "operation_id": "...", "reset_id": "..." }`. Later overlapping manual
edits or resets must be undone first. Automatic recomputation does not block undo.
Undo restores intent and recalculates current metrics; it does not roll sensor data
back to an earlier snapshot. Recent reset receipts are available after app restart.

## Validation

`just ci` runs formatting, warnings-as-errors, and unit tests. With an isolated
`SNOOP_TEST_DATABASE_URL`, `just test-db` also covers the durable worker, retries,
stale confirmations, midnight/DST boundaries, awake breaks, missing-data gaps,
full-day naps, both-domain reset, undo after recompute, and raw-data preservation.
Use the synthetic `tools/ui-fixture.sql` for simulator tests; never run fixture
writes against a production database. Rehearse migration on a private restored
backup and verify original raw data and fixed edits before deployment.
