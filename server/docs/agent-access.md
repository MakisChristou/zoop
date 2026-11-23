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
most one hour, refresh tokens at most 30 days and never longer than the approved grant. Codes are
single-use; refreshes rotate atomically. Reuse revokes the entire connection.
No implicit/password grant, token passthrough or client secret is supported.

The issuer comes from validated configuration, never request Host headers. Public
clients use exact HTTPS callbacks. Only registered HTTP `localhost` and `127.0.0.1`
`/callback` redirects allow a variable port (RFC 8252); the token exchange still
requires the exact callback used at authorization. Responses include `iss` and
preserve `state`, including denial and errors sent to verified callbacks. Unverified
callbacks never receive a redirect. Discovery advertises S256, public clients and
only Zoop's five read scopes; the 401 challenge includes resource metadata and scope.

CIMD is preferred, with rate-limited DCR retained as a fallback. Metadata URLs must
be HTTPS on port 443 with a non-root path. Fetching resolves DNS once, rejects all
private/reserved/transition addresses, pins that address set, disables proxies and
redirects, validates TLS, and caps the document at 32 KiB and the whole fetch at eight
seconds. No cookies, tokens or user data accompany the request. Only the client ID,
name, redirect URIs and supported authentication methods matter; remote logos and
JWK URLs are never fetched. `client_id` must exactly equal the document URL. The
plural authentication-method list takes precedence over the legacy preference.

The in-memory cache is capped at 128 entries and one hour, respecting shorter
`max-age`, `Age`, `no-cache` and `no-store`. Failed refreshes do not reuse stale
metadata. Only consented CIMD clients are persisted; abandoned DCR registrations
older than seven days are purged on registration. Referenced clients are preserved.
Browser consent shows the client name and callback origin. Names are self-asserted;
a familiar name is not proof of identity. Provider artwork is bundled locally and
used in saved connections only for exact known CIMD URLs.

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
120 token exchanges/minute/installation. Metadata fetching permits four concurrent
requests and 120 attempts/minute/installation. Limits are conservative self-host defaults.
Client metadata needs outbound DNS and HTTPS from the API. Compose permits that
without publishing an API port; Postgres remains on its internal network. Tokens
are bound to the configured MCP URL. After restoring to a different origin,
users must reconnect their agents rather than reuse the old credentials.
Grant last-use timestamps contain no prompts or response payloads. Do not log
Authorization headers, OAuth form bodies or health results in an upstream proxy.

Agent storage uses migration 0025; this connector update adds no migration.
Deployment is separate from implementation approval.
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

### Hosted-client verification

The optional `hosted_provider_documents_support_public_clients` test (feature
`live-provider-check`, run explicitly with `--ignored`) fetches public
provider metadata without sending credentials or health data. It is separate from
CI, which must not depend on provider uptime. Test actual hosted sign-in, a tool
call, refresh and disconnect against a synthetic-data installation before declaring
end-to-end Claude/ChatGPT compatibility. Protocol tests alone are not that proof.

Provider requirements checked against [Claude authentication](https://claude.com/docs/connectors/building/authentication)
and [OpenAI app authentication](https://developers.openai.com/plugins/build/auth).
