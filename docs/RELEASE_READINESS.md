# Release readiness

Reviewed 24 November 2026. This is dated release evidence, not a security
certification. The repository is public. App Store Connect accepted the release
of iOS 1.0 build 6 on 24 November and shows **Ready for Distribution**. The public
listing was still propagating at the first post-release check.

## Established

- Disposable Linux amd64 Compose installation, account isolation, restart and
  backup/restore are exercised in hosted CI. Web/API setup and migrations work
  without the developer's personal installation.
- Version 1.0 build 6 was manually released on 24 November, with App Store Connect
  showing **Ready for Distribution** for the approved 174-region release. The owner
  confirmed real-band sync and stable live heart rate through TestFlight. Build 6
  supersedes builds 3–5; no new binary was created for publication.
- The build 6 archive declares iPhone only and minimum iOS 26.0; its privacy
  manifest and local-network usage description are present. Hosted tests exercise
  iOS 26.5; local simulator checks exercise iOS 27.
- iOS state/transport tests cover account ownership, upload receipts, cancellation,
  credential-bearing redirects and first-run state. Synthetic UI tests cover setup,
  sign-in, goal history, loading and weight flows without using personal data. The
  23 November local UI run completed with 23 passes and no failures; the existing
  connected Health-export case was skipped because its journal was not seeded.
  That case is not counted as verified Health export behavior.
- Reachable Git history was scanned with Gitleaks. No findings remain outside the
  exact synthetic-token exception. This does not certify historical data privacy.
- Web and website dependency audits reported no vulnerabilities. The URL parser is
  patched; remaining Rust findings have narrow, dated, tested exceptions described
  in [Dependency security](DEPENDENCY_SECURITY.md).
- GitHub private vulnerability reporting, dependency alerts/security updates and
  secret scanning with push protection are enabled.
- Main requires the nine release checks from GitHub Actions and blocks force pushes
  and deletion. Tested candidate commits can advance main without a mandatory PR.
- Security scanning is repeatable in CI. Changes to date/time dependencies need
  explicit timezone and historical-result regression coverage.
- Historical data privacy was reviewed on 23 November. The owner accepted retention
  of the disclosed old sensor packets and local build metadata; previously approved
  screenshots remain authorized. See [Historical privacy review](HISTORICAL_PRIVACY_REVIEW.md)
  for scope, findings and limits. Licensing and history are unchanged. No release tag
  or container image has been published as part of this work.

## Release follow-up

1. **Retain the network qualification limitation.** On 24 November the owner
   confirmed that build 6 recovers after internet is disabled and restored, without
   signing in again. Local-network permission denial → Settings → retry remains
   unverified; the owner accepted shipping with that limitation. Automated redirect
   and receipt/queue tests do not prove iOS permission behavior. Never sign out,
   repoint a personal queue or delete the app simply to run a release test.
2. **Require green exact-commit checks.** The connector update passed web, Rust,
   PostgreSQL, security and disposable Compose checks. The iOS harness now boots its
   simulator explicitly, sets an appearance for every launch and waits for navigation
   and keyboard focus. All nine protected checks must pass before advancing main;
   do not suppress failures or treat a passing rerun as a substitute for diagnosis.
3. **Record the matched release.** Build 6’s iOS source is commit `2ef0031`. Later
   connector/server/web changes are separate from that approved binary. Record the
   exact API/web revision, migrations and verified compatibility when publishing;
   follow [Release procedure](RELEASING.md). Linux arm64 and prebuilt images are not
   claimed as validated distribution paths. The historical-data review is complete
   with informed owner acceptance; do not describe the history as fully anonymous.
4. **Complete authorized publication.** On 24 November the owner authorized releasing
   build 6 and then publishing the working App Store link in the website and guides.
   Apple accepted the release and shows **Ready for Distribution**. Release tags and
   packages are outside this publication scope. Add the store download link only
   after it works publicly.

## Final sign-in check, 24 November

The isolated reviewer installation passed a fresh native login and authenticated
reads for sleep, workouts, weight, daily summaries, profile and recovery. Unowned
device access returned 404, administrator access was denied, unauthenticated data
access was denied, and logout invalidated the test session. No health data or
account settings were changed. This is an API smoke check, not an additional iPhone
UI test.

The reviewer API/web configuration pins both to
`8ac8beafd8583337e3991090c743c79e6d5e1570` (migrations through `0021`). The personal
installation configuration pins both to
`f6ecf9f40c397fb871deb9a33dafc1bf960460ec` (migrations through `0025`), where the
owner tested build 6. These are existing compatibility observations, not a
deployment of the newer connector changes on main. Build 6's app sources remain
unchanged in the current checkout. The VO₂ research remains outside the release.

Re-run the required checks against the exact commit being published. The latest
workflow results, not old test counts in a checklist, are the evidence for a new
candidate. A hosted demo must remain synthetic and isolated from personal data.
