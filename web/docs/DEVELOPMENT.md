# Development and deployment

Start with the [README](../README.md). The frontend is a static React application;
Zoop API owns authentication, authorization, health metrics and persistence.

## Checks

```sh
npm test
npm run build
npx playwright install chromium
npm run test:e2e
nix build
```

On Nix Linux, use the bundled Chromium rather than downloading a browser:

```sh
nix develop
export CHROMIUM_PATH=$(command -v chromium)
npm run test:e2e
```

Browser tests cover navigation, chart selection, desktop/mobile layouts, incomplete
data, errors and admin visibility. They use synthetic responses. For API contract
and authentication changes, also run the integration test:

```sh
bash tools/test-api.sh
```

The script defaults to the sibling `../server` workspace; `ZOOP_API_DIR` can
override it. Run it in the existing web development shell.

This creates a temporary PostgreSQL cluster and synthetic accounts, verifies
cross-user denial and logout, and removes its fixtures. It does not use the
configured production database.

## Deployment

The flake exports `packages.<system>.default` and `nixosModules.default`. Pin the
GitHub input in your host's `flake.lock`; the server does not need a mutable source
checkout. `nix build` produces the static site, not a live deployment.

The NixOS module serves the build through Nginx and proxies `/v1/` to `apiUrl`.
It enables HTTPS and ACME by default. Configure `security.acme.acceptTerms` and
`security.acme.defaults.email` in the host configuration. With a different reverse
proxy, serve the built files and preserve the same-origin API arrangement.

Provision the API first. Its private-account mode requires an administrator and
explicit device ownership. Set its exact public browser origin, without a trailing
slash, and keep the API and database ports off the public network. See the
[account guide](../../server/docs/private-web.md).

## Accounts and writes

Browser sessions use HttpOnly cookies. Goal changes require both the configured
Origin and the current revision; photo uploads require that Origin too. Both are
restricted to the account's own device. Other measurement writes remain iPhone-only.

Profile photos are normalized JPEGs stored privately in PostgreSQL by the API.
Account creation, password recovery and disabling accounts are operator CLI tasks.
Admin status does not bypass health-data ownership.

## Documentation screenshots

The README images show the running frontend with synthetic data, captured from the
current UI. They are curated documentation assets, not production account exports.
Keep screenshots free of credentials, account identifiers and browser overlays.
