# Private web accounts

Optional multi-user authentication for Zoop web. Disabled by default: existing single-user installations continue to use their current token. Migration 0017 is additive and does not rewrite health records.

## Prepare a rollout

1. Back up PostgreSQL and verify a restore to a separate development database.
2. Build the API and apply `zoop migrate --config /path/to/zoop.toml`.
3. Create the owner's admin account and assign every existing device. Give each additional person a separate account and device token.
4. Import the current iPhone token for its owner before enabling private mode. The phone can keep its existing configuration. A token can belong to only one account.
5. Enable private mode with the exact browser origin, test in staging, then schedule a production rollout. This document is not deployment authorization.

Use protected files for credentials (`chmod 600`); values must never appear in shell arguments or source control:

```sh
zoop account create --email owner@example.com --password-file /run/secrets/owner-password --admin --config /path/to/zoop.toml
zoop account bind-device --email owner@example.com --device DEVICE_SERIAL --config /path/to/zoop.toml
zoop account import-token --email owner@example.com --token-file /run/secrets/phone-token --config /path/to/zoop.toml
```

For subsequent users omit `--admin`, reserve their device, and sign in on the phone with the new account. Device reassignment is deliberately not automatic.

```toml
[web]
enabled = true
origin = "https://health.example.com"
```

The server refuses private mode until an enabled admin exists and every existing device has an owner. There is no fallback to the shared installation token in private mode. Bind the API to loopback behind the dashboard's same-origin HTTPS proxy; do not expose its port directly.

Nix exposes `services.zoop.web.enable` and `.origin`; both remain inactive until explicitly configured. Zoop web provides the separate static frontend/Nginx module.

## Access and recovery

- Accounts own devices; admin status never bypasses health-data ownership.
- Browser sessions are random, hashed at rest, HttpOnly, SameSite Strict and Secure over HTTPS. They expire after 12 hours. Browser health writes are denied.
- Passwords use Argon2id. Login is rate-limited in PostgreSQL; no browser token is stored in local storage.
- `zoop account reset-password --email … --password-file …` revokes existing browser sessions, including concurrent login attempts. Phone tokens, including imported legacy tokens, are also revoked.
- `zoop account disable --email …` disables access and revokes browser and phone credentials.
- Account creation, ownership and recovery are operator CLI operations. No public registration or email reset exists in v1.

Admin statistics expose aggregate queues, failures, ingestion and worker heartbeat status. Request counts reset on service restart; latency covers the most recent 2,048 requests. Health payloads, serial numbers and raw error strings are excluded.

## Validation and rollback

Run `just ci`, then `ZOOP_TEST_DATABASE_URL=… cargo test -p zoop-api --test accounts -- --ignored` against a disposable development database. Also run `just test-db test-progress-db` with that variable set. Account tests exercise every device route, both ingest routes, admin isolation, token migration, session expiry/revocation and origin/rate limits.

Before enabling multiple users, verify the owner's iPhone can still read and upload with its imported token. If rollout fails, remove public web access and restore the prior application/configuration under maintenance. Do not disable private mode while leaving a multi-user API publicly reachable: the old installation token has installation-wide scope. The additive account tables can remain; no raw data rollback is required.

## Native sign-in

`POST /v1/auth/native/login` accepts email/password JSON and returns a private phone
credential. Use HTTPS. The iPhone keeps it in Keychain; the server stores only its
hash. Browser-origin native-token requests are rejected. Browser cookies permit only owner-scoped goal management; other health writes remain blocked.
`GET /v1/auth/me` returns the current account and assigned devices for either client.
`POST /v1/auth/native/logout` revokes the presented phone credential. Tokens remain
valid until sign-out, password recovery or account disable; no expiry or refresh-token
flow is claimed. Password recovery now revokes **all** phone tokens, including
imported legacy credentials, as well as browser sessions.

There is no automatic device claiming. The operator assigns serials explicitly.

### Goal management

Browser sessions may update only their own `PUT /v1/devices/{id}/weight-goal`, with the exact configured Origin and current revision. Other health writes remain blocked. Goal history reads use the same ownership checks as measurements.
