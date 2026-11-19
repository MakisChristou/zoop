# Reliable history: rollout and recovery

## Upload contract

`POST /v2/ingest` accepts the v1 body plus optional `upload_id` on each frame.
New clients generate and persist a UUID before sending. A null ID is reserved for
queued legacy rows; it remains in the `(device_id, client_seq)` namespace. UUID rows
are unique by `(device_id, upload_id)`, so a fresh installation can restart its
sequence counter safely. Identity conflicts never overwrite bytes.

The response includes `accepted`, `duplicates`, `rejected` for diagnostics and a
`results` array with `client_seq`, `upload_id`, `status` and optional `reason`.
Statuses are `stored`, `duplicate`, `rejected`, `conflict`. A client validates exactly
one matching receipt per submitted frame before applying the response atomically.
It deletes only stored/duplicate rows, holds rejected/conflicting rows for review,
and retries unacknowledged rows with their original identity. Lost HTTP responses
are harmless retries. A database failure can leave an accepted prefix of a batch;
retrying the full batch deduplicates that prefix.

The legacy route remains available, but a partial batch returns 400 so older clients
cannot mistake aggregate success for permission to delete every submitted frame.
A malformed envelope is rejected; a valid envelope with an unfamiliar or malformed
semantic payload is retained raw for a future decoder fix.

## Staged deployment

1. Take a private database dump and **restore it successfully** into an isolated
   database. Record source-frame counts and a digest of immutable payloads. Exercise
   migration 0006 and backfill on the restored copy before production.
2. Deploy the new backend with `worker.history_enabled=false` (NixOS:
   `services.zoop.historyEnabled=false`). Migrations apply before service startup.
   Intake, v1 compatibility and decoding stay enabled; jobs accumulate durably.
3. Install the upgraded phone app without uninstalling it. Verify legacy pending
   rows migrate intact, new uploads use UUIDs, and per-frame receipts drain the queue.
4. Enable history processing, restart Zoop and monitor the authenticated processing
   endpoint. Check failures, the oldest pending date, available day load and retained
   labels. An empty completed day is valid. Backfilled sessions must remain silent.
5. Verify the pre-existing raw payload digest is unchanged. Keep the backup private.

The decoder and analyzer have separate progress. Decode progress is recorded per
raw frame/protocol version; analytics uses per-device, date, time-zone and method
jobs rather than a single timestamp cursor. Sample changes advance job generations
in the decode transaction. Failed jobs retry after capped exponential backoff;
expired leases can be reclaimed. Publication checks both lease ownership and input
generation before changing results or completion markers.

## Recovery boundaries

Pause analysis with `history_enabled=false` if a calculation needs investigation;
uploads and raw storage continue. Resume to drain unfinished work. Use the processing
endpoint and persisted job errors to distinguish bad inputs from a stopped worker.
A stopped worker makes readiness fail; systemd restarts an unexpectedly exited task.

After migration 0006, **do not roll back to a pre-v2 backend binary**. The old unique
constraint was replaced by separate legacy/UUID indexes, and new installs may reuse
sequence numbers. Roll back only to a compatible v2 build, or leave analysis paused
while fixing forward. Restoring a backup over a live database would discard uploads
received since the dump and is not an automatic recovery action.

No finite app queue can survive uninstalling the app or losing the phone. iOS also
controls background execution. The persistence barrier protects history ACK order
while the app runs; it does not guarantee continuous collection while suspended.
