# Agent access boundary

The `zoop-agent` crate exposes Streamable HTTP MCP and a bounded JSON read API.
It is mounted only in private-account mode. No model, provider key, arbitrary SQL,
network-fetch tool or write tool is included. The normal Docker installation runs it
inside the existing API process.

## Authentication and isolation

- Browser management uses existing HttpOnly sessions and exact same-origin checks.
  Consent issuance locks account/session/ownership against revocation and deletion.
- Every grant fixes an account, owned device, category scopes, timezone, rolling
  history allowance and absolute expiry. Administrators have no health-data override.
- Agent credentials live in separate tables. Random 256-bit keys, authorization
  codes, access tokens and refresh tokens are persisted as SHA-256 digests only.
  Responses containing credentials are no-store. Keys are returned only at creation.
- The ordinary API rejects integration credentials before parsing unrelated bodies.
  Agent routes reject phone/global credentials and browser cookies.
- Reads validate credential expiry, grant expiry, revocation, enabled account and
  current device ownership on every request. MCP is stateless even for legacy
  clients; an MCP session identifier never conveys authorization.
- SQL triggers revoke grants on password rotation, account disabling and ownership
  update/removal. Account deletion cascades agent grants and credentials. No change
  is made to normal raw-frame retention.

## OAuth

Authorization code with PKCE S256, exact registered redirects and exact resource
binding (`<configured web origin>/mcp`). Codes live two minutes, access tokens at
most 15 minutes, refresh tokens no longer than the approved grant. Codes are
single-use; refreshes rotate atomically. Reuse revokes the entire connection.
No implicit/password grant, token passthrough, client secret or remote metadata
fetch is supported.

The issuer comes from validated configuration, never request Host headers. Public
clients register exact HTTPS callbacks or HTTP loopback callbacks. Dynamic client
registration is supported for interoperability; client metadata-document fetching
is deliberately absent, avoiding an SSRF surface. Browser consent shows the
registered name and callback origin. A name is not a verified identity.

The integration is one resource: MCP and its equivalent `/v1/agent/*` read endpoints
accept its access tokens. Neither accepts another resource's token. Access keys are
limited by the same grant without requiring an OAuth client.

## Data contract

Scopes are `sleep:read`, `recovery:read`, `activity:read`, `weight:read`, `goals:read`.
Sleep excludes physiology; Recovery includes nightly HRV/RHR; Activity includes
workout heart rate. Recovery excludes internal sleep-component diagnostics and
baseline-history counts. Summary fields and tool discovery are scope-filtered, and each
tool independently checks permissions. Goals also needs Weight for measured
progress. Full-goal progress is withheld when its baseline predates the requested
window or its calendar differs from the consent timezone. Backend Recovery is reused, never calculated independently by the adapter.

Daily step/weight/sleep projections reuse the existing shared-dashboard queries;
steps always use walking/running-filtered counts. Effective session corrections,
pending metrics and source priority are preserved. No free-form edit notes, profile
photos, serials, source identifiers or email addresses enter tool results.

`generated_at` is response creation time, not measurement freshness. Individual
readings carry dates, sessions carry pending flags, and recovery keeps its existing
availability state. Requests are bounded to 90 days, 2,000 sessions/readings and
512 KiB responses. Oversized results fail explicitly rather than silently truncate.
No raw-data re-derivation is triggered. Existing rebuildable day-summary caches may
refresh on reads, as they do for dashboards; health records/goals are not changed.

## Resource limits and operations

Two concurrent agent requests per API process, a 20-second request deadline,
60 requests/minute per grant, bounded body sizes, 50 active connections/account,
20 connection issuances/hour/account, 30 client registrations/hour/installation and
120 token exchanges/minute/installation. Limits are conservative self-host defaults.
Grant last-use timestamps contain no prompts or response payloads. Do not log
Authorization headers, OAuth form bodies or health results in an upstream proxy.

This slice adds migration 0025. Deployment is separate from implementation approval.
Back up before upgrading; existing accounts and native credentials remain unchanged.
The public-client records contain no health data or secrets. Expired access tokens
are pruned during grant creation; consumed codes/refreshes remain for replay checks
for the lifetime of their connection.

## Verification

Run `cargo test -p zoop-api --test agents -- --ignored` with an explicitly disposable
`ZOOP_TEST_DATABASE_URL`; each test uses its own schema. These tests exercise the
full application router, not only helper functions. Run the full workspace suite,
Clippy, browser tests and disposable Compose restore test before deployment.

Standards: [MCP authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization),
[MCP security](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices),
[PKCE](https://www.rfc-editor.org/rfc/rfc7636),
[resource indicators](https://www.rfc-editor.org/rfc/rfc8707).
