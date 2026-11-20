# Zoop web

A private dashboard for your wearable data. Sleep, activity, weight and goals, connected to [Zoop API](https://github.com/MakisChristou/zoop-api).

React, TypeScript and Recharts. Static files served by Nginx; the Rust API owns authentication and data. Fonts are bundled locally. No analytics or third-party requests.

## Develop

Use Node 24, or `nix develop`:

```sh
npm ci
npm run dev
```

The dashboard listens on `127.0.0.1:5173` and proxies requests to `127.0.0.1:18471`. Set `ZOOP_API_URL` to change the development upstream. Enable the API's private-account mode with `web.origin = "http://127.0.0.1:5173"` and provision an account first. See the API's `docs/private-web.md`.

## Check

```sh
npm test
npm run build
npx playwright install chromium
npm run test:e2e
nix build
```

On Nix Linux, set `CHROMIUM_PATH=$(command -v chromium)` inside `nix develop`. Browser tests cover navigation, errors, missing data, chart selection, mobile layout and admin visibility. The real-API integration test uses a fresh temporary PostgreSQL cluster and synthetic
accounts, checks cross-user denial and logout, then removes its fixtures:

```sh
ZOOP_API_DIR=/path/to/zoop-api nix develop --command bash tools/test-api.sh
```

This requires a local API checkout and never connects to your configured production
database. Ordinary PR checks use mock responses; run the real-API test before a
release or an authentication/API contract change.

## Accounts

An operator creates accounts and assigns devices. Each account sees only its own records. Admins additionally see aggregate ingestion, jobs, worker health and request statistics; admin status does not grant access to other users' health data.

Browser sessions use HttpOnly cookies. You can manage your own cut, bulk and maintenance phases on the web. Each phase has its own steps target and weekly weight outlook. Profile photos can be cropped and updated from the account menu; the same small JPEG is stored in PostgreSQL and used on iPhone. Measurements remain read-only. Photo uploads require the configured origin; goal writes also require the current revision; admin status never bypasses ownership. Password recovery is an operator command in this first version; there is no public registration or email recovery flow.

## Self-host

The flake exports a static package and a NixOS module:

```nix
imports = [ inputs.zoop-web.nixosModules.default ];
services.zoop-web = {
  enable = true;
  domain = "health.example.com";
  apiUrl = "http://127.0.0.1:8471";
};
```

Provision the matching API first, set its exact HTTPS origin, and keep its port private. The module serves both UI and `/v1/` on one origin and enables HTTPS. Configure ACME's email and terms as usual. Building or importing the flake does not deploy it.

The dashboard currently loads one year of history, up to 1,000 sleep sessions and 500 workouts, with visible notices when a limit is reached. Missing measurements remain empty. Sleep is displayed without an invented percentage because the iPhone's sleep goal is not yet stored by the API.

For contributions and vulnerability reporting, see [CONTRIBUTING.md](CONTRIBUTING.md)
and [SECURITY.md](SECURITY.md).

MIT. Bundled font and dependency licenses remain applicable.
