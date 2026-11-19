# Zoop web

A private, read-only dashboard for your wearable data. Sleep, activity, weight and goals, connected to [Zoop API](https://github.com/MakisChristou/zoop-api).

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

On Nix Linux, set `CHROMIUM_PATH=$(command -v chromium)` inside `nix develop`. Browser tests cover navigation, errors, missing data, chart selection, mobile layout and admin visibility. The optional live test requires a separate development API with synthetic `admin@example.test` / `member@example.test` accounts owning `DEMO-A` / `DEMO-B`, and today's weights of 64.2 / 89.7 kg. Set `ZOOP_E2E_REAL=1` and `ZOOP_E2E_PASSWORD` to run it. Never point fixture tests at a real user's database.

## Accounts

An operator creates accounts and assigns devices. Each account sees only its own records. Admins additionally see aggregate ingestion, jobs, worker health and request statistics; admin status does not grant access to other users' health data.

Browser sessions use HttpOnly cookies. Browser health writes are rejected by the API. Password recovery is an operator command in this first version; there is no public registration or email recovery flow.

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
