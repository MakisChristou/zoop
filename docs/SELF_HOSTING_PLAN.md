# Self-hosting direction

This records the next installation slice. It is not an installation guide and the
complete stack described here is not yet implemented.

## Installation boundary

- Docker Compose runs the web app, API and PostgreSQL with persistent storage.
- The stack exposes an internal HTTP endpoint with web and API on one origin.
- Operators choose their own access arrangement: Caddy, Nginx, a VPN or another
  network setup. Zoop does not manage DNS, certificates, TLS termination or routers.
- PostgreSQL stays inside the stack. No host-specific configuration is generated.
- Configuration states the browser origin explicitly; session and origin protections
  remain enforced regardless of the operator's chosen network arrangement.
- Current iPhone sign-in accepts HTTPS and loopback HTTP only. Supporting a private
  HTTP server on LAN/VPN requires a deliberate app change and validation in this
  installation slice. Do not claim it already works or silently relax transport rules.

## First run

Use a one-time operator setup code to create the first administrator. Guide the
owner through account creation, phone connection, explicit device ownership and
receipt of the first recording. No anonymous first-visitor account claiming.

## Public project

The proposed public home is `zoop.health`, with documentation under `/docs` and a
synthetic-data demo at `demo.zoop.health`. The site and demo must be separate from
personal installations, credentials and databases. Domain configuration, hosting
and publication require their own approval.

## Release checks

Before calling installation supported, validate a clean Compose start, real web/API
interaction, two-account isolation, upgrade from the preceding release, and backup
restoration into an empty instance. Keep a physical-iPhone check for collection and
upload recovery. Version images together and document compatible client versions.
