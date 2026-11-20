# Shared dashboards

Owners choose one device, explicit metrics and their order. Visitors receive only
selected daily scalar series: sleep duration, Recovery, Load, filtered steps,
workout count, weight, HRV and resting heart rate. No raw frames, ECG, workout
metadata, email or device/account identifiers are returned. Display name and photo
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

Limits: 50 dashboards per account, eight distinct allowlisted widgets, 16 KiB request
bodies, four concurrent projections, existing four-slot password hashing bound,
120 public requests/minute globally and 30/minute per resolved share. Rate-limit
keys are bounded (one global key and one per existing share), not attacker-supplied.
A busy public endpoint returns 429 rather than starting unlimited work.

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
