# Self-hosting roadmap

The first installation slice is implemented. See [Run your own Zoop](SELF_HOSTING.md)
for Docker Compose, browser setup, explicit device ownership, updates and backups.

The stack serves one HTTP origin. Operators choose their own network access;
Zoop does not manage DNS, certificates, proxies, routers or host configuration.

Before public launch:

- Complete [release readiness](RELEASE_READINESS.md), including retained-history privacy review.
- Validate arm64 and an upgrade from the first versioned release.
- Approve versioned container publication and a supported client/server release policy.
- Finish [App Store checks](APP_STORE.md) and real-device onboarding validation.

Future slices require approval: a public home at `zoop.health`, documentation and
a synthetic demo; broader browser-based administration and safe reprocessing.
Public demos must use separate databases and credentials from personal installations.
