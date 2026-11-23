# Release readiness

Reviewed 23 November 2026. This is dated release evidence, not a security
certification. The repository is public; the iPhone app is not yet publicly
available on the App Store.

## Established

- Disposable Linux amd64 Compose installation, account isolation, restart and
  backup/restore are exercised in hosted CI. Web/API setup and migrations work
  without the developer's personal installation.
- Version 1.0 build 6 is **approved, Pending Developer Release**, verified in App
  Store Connect on 23 November. Manual release remains selected. The owner confirmed
  real-band sync and stable live heart rate through TestFlight. Build 6 supersedes
  builds 3–5 as the release candidate; no public release has occurred.
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
- Licensing and history are unchanged. No release tag or container image has been
  published as part of this work.

## Remaining release gates

1. **Complete real-device network qualification.** Build 6’s normal connection and
   sync are user-confirmed. Explicit offline → restored connection/upload recovery
   and local-network permission denial → Settings → retry still need their own
   observed results. Automated redirect and receipt/queue tests pass; these do not
   prove iOS permission behavior. Never sign out, repoint a personal queue or delete
   the app simply to run a release test.
2. **Require green exact-commit checks.** The connector update passed web, Rust,
   PostgreSQL, security and disposable Compose checks. The iOS harness now boots its
   simulator explicitly, sets an appearance for every launch and waits for navigation
   and keyboard focus. All nine protected checks must pass before advancing main;
   do not suppress failures or treat a passing rerun as a substitute for diagnosis.
3. **Record the matched release.** Build 6’s iOS source is commit `2ef0031`. Later
   connector/server/web changes are separate from that approved binary. Record the
   exact API/web revision, migrations and verified compatibility when publishing;
   follow [Release procedure](RELEASING.md). Linux arm64 and prebuilt images are not
   claimed as validated distribution paths. Historical sensor captures/build material
   still need the approved privacy review before promoting the repository.
4. **Approve publication separately.** The App Store candidate is selected and
   approved. Public app release, website deployment, release tags and packages remain
   separate approvals. Add the store download link only after it works publicly.

Re-run the required checks against the exact commit being published. The latest
workflow results, not old test counts in a checklist, are the evidence for a new
candidate. A hosted demo must remain synthetic and isolated from personal data.
