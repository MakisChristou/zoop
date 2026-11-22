# Release procedure

Zoop ships an iPhone app, API and web dashboard. The API owns stored measurements
and derived metrics. Ship the web dashboard from the same source revision as its
API; record the matching iPhone version and build in each release's notes.

## Prepare a candidate

1. Choose an exact commit and run all checks: iOS, Rust, PostgreSQL regressions,
   web, website, security and the disposable Compose restore test.
2. Record that commit, app version/build, migration range and tested platforms.
   Publish known limitations and the backup/upgrade steps with the release.
3. Test the signed app through TestFlight, including first-run login, real-band
   sync, reconnect and the minimum supported iOS version. Keep personal data out
   of public CI artifacts; use synthetic accounts and screenshots there.
4. Request approval before replacing/submitting an App Review build, publishing
   a release/tag or container image, or activating a deployment.

## Upgrade safely

Back up the database first. Upgrade the API and web together, then the iPhone app.
Check database readiness, login and sync after the upgrade. Do not roll an older
API back over a newer schema unless that release explicitly supports it; restore
into a separate empty database when rehearsing a rollback.

The first distribution currently builds Docker images from source. Once a
versioned release is published, installation instructions should pin that release
instead of following `main`. Do not advertise prebuilt images or additional CPU
architectures before testing and publishing them.

## Compatibility

Keep `/v1` changes additive for released clients. Add optional response fields,
retain existing meanings and tolerate older requests. A required request field,
removed endpoint or changed metric meaning requires an explicit compatibility plan
and tests against the oldest supported app. New required backend capabilities must
produce a useful upgrade message rather than an empty screen.

A release is ready only when the recorded app/API pair passes these checks; the
internal Rust crate version alone is not a compatibility guarantee.

## Updating protected main

Push a candidate branch and wait for its required checks, then fast-forward `main`
to that exact commit. Pull requests are welcome but not required. Do not bypass
checks, force-push or delete `main`. All validation workflows run on candidate
branches; the website deploys only through its separately approved manual workflow.
