# Workout corrections

Automatic detection remains on the server. User decisions live independently of
versioned detector candidates and raw sensor history. Migration 0007 seeds stable
session identities from the currently visible workouts, including existing type
labels and old numeric notification links. Sleep stays at version 2. Workout/day
analysis version 3 adds interval projections and calendar-day calorie allocation.

## User rules

- Edit type, start, or end; add a missed workout; merge neighbouring workouts; split
  at an interior time; remove a false detection; undo or restore a removed workout.
- Merging produces one continuous interval including rests. Splitting partitions
  the complete interval into two adjacent, half-open intervals.
- Adding, editing, merging and both split outputs require decoded strap readings.
  An undecoded raw frame alone is insufficient. Partial recordings are allowed;
  missing HR, calories, zones and steps stay null, with coverage reported separately.
- User-selected intervals need not meet automatic detection's 10/20-minute limits.
  They must have positive duration, end in the past, and last at most 24 hours.
- Outputs may not overlap another active workout. Resolve the times or explicitly
  merge the conflicting workouts. Merge cannot silently swallow an unselected one.
- Daily awake Load and measured step totals are independent of workout corrections.
  Workout metrics use real samples inside the selected bounds. Daily workout calories
  use the intersection with each local day, never the entire cross-midnight session
  on both dates. Its start day's historical physiology is used for all portions.
- Corrections, undo and backfill are silent. Only a new eligible automatic session
  may generate a detection notification.

## Storage and concurrency

`workouts` remains the versioned candidate table. `workout_sessions` is the effective
projection with stable ids, revisions, status, pending metrics and optional fixed
bounds. `workout_corrections` stores command identity, exact request, before-state,
affected session ids and interval ownership. `workout_aliases` preserves legacy links.
`workout_labels` is retained as legacy history; normal writes now use correction
commands, including the compatible type-only endpoint.

Each correction owns the envelope of its input and output intervals. Automatic
candidates are cut around active ownership and detected separately inside each
remaining fragment. The detector cannot join across the owned interval or recreate
trimmed/removed fragments. Nested corrections retain earlier ownership until their
own undo. A type-only command keeps the currently displayed bounds. Migrated type labels
receive the same ownership and undo semantics as new corrections.

Both correction writes and day publication lock the device before analysis jobs.
Saving the command and invalidating every affected calendar date plus context days
is one transaction. The existing generation/lease fence rejects workers calculated
before a concurrent correction. Metrics and daily aggregates publish atomically.
Automatic identities are reconciled deterministically by overlap across shifts and
algorithm changes. Fixed user sessions never depend on candidate row survival.

Undo restores previous intent, requests fresh metrics, and deactivates that command's
ownership. All affected sessions must still point to the command; otherwise later
edits must be undone first. Undo also checks newly overlapping workouts. New ids are
retired rather than reused, and merged-away links reference the surviving session.

## API

Existing authenticated routes continue to serve the effective projection:

- `GET /v1/devices/{serial}/workouts?from=...&to=...&status=active&limit=500`
  selects by interval overlap. `status=removed` exposes restorable removals.
- `GET /v1/devices/{serial}/workouts/{id}` resolves current and legacy ids, including
  removed/superseded records. Inspect `status` and `replacements` for old links.
- `PUT /v1/devices/{serial}/workouts/{id}/kind` remains a type-only compatibility API.
- `POST /v1/devices/{serial}/workouts/corrections` accepts an idempotent command.

```json
{
  "operation_id": "db2451fa-940e-4600-8aba-b711994c5b64",
  "action": "edit",
  "targets": [{ "id": 42, "revision": 3 }],
  "intervals": [{
    "start_ts": "2025-01-01T18:00:00Z",
    "end_ts": "2025-01-01T19:00:00Z",
    "kind": "resistance"
  }]
}
```

Actions are `add`, `edit`, `label`, `merge`, `split`, `remove`, and `undo`. Add has no
input targets; edit/label has one; merge has 2–20; split/remove has one. Split has two
ordered outputs; remove has none. Undo has only `undo_id`, naming the prior operation.
Each request also has a new `operation_id`. Reuse it with identical content after a
lost response; change it when the draft changes. A duplicate returns the same receipt.
The receipt contains `operation_id` and `workout_ids`, including replaced inputs.
Read their current states after saving.

Stale revisions, overlaps and reused request ids with different content return 409.
Invalid intervals or missing sensor data return 400 with an actionable message.
Unknown resources return 404. The app retains the form on unsuccessful saves and
shows `metrics_pending` until calculation completes.

## Validation and rollout

Run `just ci`, then `just test-db` with an isolated `SNOOP_TEST_DATABASE_URL`. The
correction tests exercise nested undo, partial/missing data, retries, revision
conflicts, worker fencing, version upgrades, overlap prevention, midnight/DST,
historical profiles, and HTTP compatibility. Synthetic fixtures contain no personal
data. Rehearse migration against a private restored backup before production.

Deploy the backend and verify the new routes before installing the app. Recheck
pending/failed jobs, carried labels, stable ids, unchanged raw bytes and unchanged
sleep version. Finally correct an actual walk and gym visit on the phone, sync again,
and confirm the result persists. Synthetic tests do not establish detector accuracy.
