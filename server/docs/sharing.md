# Shared dashboards

Owners choose one device, explicit metrics and their order. Visitors receive only selected widgets. Daily series cover: sleep duration, Recovery, Load, filtered steps,
workout count, weight, HRV and resting heart rate. Optional summary and activity cards
reuse the private dashboard presentation:

- **Daily rings:** sleep duration, Recovery score/state/band/version and Load for the last
  day of the shared period. All three use the same date; missing readings stay empty.
  Recovery uses the private insights calculation, without exposing its inputs.
- **Every day:** daily Load plus per-day, per-sport workout counts and duration totals.
- **Recent activities:** local date, sport, duration and Load for each workout.
- **By sport:** workout counts and duration totals grouped by sport.

These cards have separate selection keys; existing links never gain them implicitly.
Only active, fully derived, completed workouts within the selected range are included.
No raw frames, ECG, exact workout timestamps, workout IDs, heart-rate summaries,
email or device/account identifiers are returned. Display name and photo
are opt-in; empty identity fields disclose nothing.

## Access

- Owner routes: `GET/POST /v1/shares`, `PUT/DELETE /v1/shares/{id}`,
  `POST /v1/shares/preview`. Browser account sessions only; writes require the
  configured Origin. Admin status does not bypass ownership.
- Visitor route: `POST /v1/public/dashboard` with `token`, optional `password`
  and optional `year`. It never treats the token as account authorization.
- Links use `#share/<token>`. The fragment stays out of HTTP request URLs, access
  logs and referrers. Send capabilities/passwords only in POST bodies; operators
  must not enable body logging for these routes.
- Tokens contain 256 bits of OS randomness. Lookup uses SHA-256; the capability is
  also stored in the owner's sharing row so Copy link works after a reload. Treat
  the database and backups as private. Debug output redacts sharing records.
- Passwords use the existing Argon2id implementation. Omission preserves an existing
  password; an explicit empty string removes it. Plaintext is never persisted.
- Every visitor request checks expiry, enabled state, owner enabled state and device
  ownership. The share revision is checked again after projection, fencing concurrent
  revocation/scope/password changes. Edits use optimistic revisions.
- Responses are `Cache-Control: no-store`; the visitor page uses noindex and sends
  no account cookies. Revocation cannot recall data already viewed or copied.

## History and metrics

Default: rolling last 30 local calendar days and seven-day expiry. `expires_at: null`
means no expiry. `all` includes subsequent readings; `fixed` requires both dates.
All ranges stop at today in the device profile's timezone. Long ranges are paged by
calendar year, at most 366 days. Visitor parameters cannot expand an authorized range.
Earliest-history metadata considers selected categories only.

Measurements use the existing server definitions: effective main sleep, daily Health-
priority weight and walking/running-filtered steps. Recovery invokes the identical
quality-gated calculation as private insights, from one bounded snapshot including
28 prior days. No client derives scores. Missing measurements stay null. Reading
steps may refresh the existing derived daily cache; it never edits health records.

Limits: 50 dashboards per account, twelve distinct allowlisted widgets, 16 KiB request
bodies, four concurrent projections, existing four-slot password hashing bound,
120 public requests/minute globally and 30/minute per resolved share. Rate-limit
keys are bounded (one global key and one per existing share), not attacker-supplied.
A busy public endpoint returns 429 rather than starting unlimited work.
Recent activities is bounded to 10,000 workouts per year page; larger results request
a shorter period rather than silently truncating. The other activity cards aggregate
in the database and do not expose individual workout rows.

## Verification and rollout

Run `just ci`, then the sharing and insights integration tests with
`ZOOP_TEST_DATABASE_URL` pointed at a development database. Tests create isolated
schemas; never point them at production. Coverage includes multiple owners, admin
isolation, password changes, expiry/revocation, stale edits, DST, fixed/rolling/year
bounds, selected-field projection and Recovery parity after corrections.

Apply migration 0021 before activating the new API/web pair. It creates a separate
sharing table and owner index; it does not rewrite health data. Back up first. The
older API/web pair can run with this additive table for rollback. Public dashboards
are opt-in: migration creates no links. Deploying requires operator approval.

No embed support, public directory, uploads, account login delegation or general
public health API is provided by this slice.

## Layout

Widgets snap to a two-column grid. Charts offer `standard` (one column) and `wide`
(two columns); rings, heatmaps and activity lists retain their fixed footprints.
Owners drag from the library or move handles; arrow keys and touch reorder buttons
provide alternatives. Collisions push cards down. The server rejects arbitrary sizes,
overlaps, unknown keys and out-of-bounds rows. Shared layouts remain in config JSON. Legacy
links with no layout receive an automatic layout. Mobile viewers stack widgets in
visual reading order. A year-shaped heatmap leaves dates outside the shared period
blank and disabled; its shape does not widen the authorized data range.

The optional `heatmap_year` setting shares the 365 days ending on the displayed
period’s last day for the activity heatmap only. It defaults to false, so existing
links retain their selected scope. Other widgets still use the dashboard period.

The `daily_rings` projection includes `sleep_goal_minutes`, the same server-owned
sleep target used by the signed-in dashboard and iPhone. The Sleep arc fills at
that target; the centre continues to show measured sleep duration. See
[Sleep goal](SLEEP_GOAL.md).


## Private dashboard editor

`GET/PUT /v1/dashboard-layouts/{device}` reads/saves an account/device layout.
Browser sessions and ownership are required; saves also check Origin and an optimistic
`revision` (zero for the first save). Migration 0024 adds the private preferences table,
with account/device deletion cascades. It creates no public links and changes no health
records. Back up before applying the migration with the API/web update.

The private Today page keeps its existing default until customized. Both editors use
the same widget canvas and server projection. Selected historical days retain their
own 30-day window; saved layouts do not change metric definitions. Layout-only edits
reuse the projection, while metric/range changes cancel and replace it. Save commits
the draft; cancel leaves the saved dashboard unchanged. Existing shared visitors keep
the last saved configuration throughout editing. Mobile stacks cards in visual order.

Older API versions do not recognize the optional layout `size` field. Once a widened
layout is saved, rollbacks must preserve this validation contract (or remove its size
presets first). The additive preferences table itself can remain in place.
