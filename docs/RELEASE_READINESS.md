# Release readiness

Reviewed 22 November 2026. This is dated release evidence, not a security
certification. The repository is public; the iPhone app is not yet publicly
available on the App Store.

## Established

- Disposable Linux amd64 Compose installation, account isolation, restart and
  backup/restore are exercised in hosted CI. Web/API setup and migrations work
  without the developer's personal installation.
- User-confirmed TestFlight 1.0 (4) connects to a real band, shows live heart rate
  and completes sync. Build 3 remains the pending App Review submission; it has
  not been replaced by later test builds.
- iOS state/transport tests cover account ownership, upload receipts, cancellation,
  credential-bearing redirects and first-run state. Synthetic UI tests cover setup,
  sign-in, goal history, loading and weight flows without using personal data.
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

1. **Qualify the final iPhone build.** A live-heart-rate source-switching fix is
   prepared for build 5. Verify that actual strap readings update normally and a
   stale reading gains a timestamp without jumping to an older chart value. Keep
   the user's account, upload queue and Bluetooth bond intact.
2. **Verify the supported iOS range.** Build 5 sets the approved minimum to iOS 26;
   hosted tests use iOS 26.5 and local tests use iOS 27. Older systems are no longer
   advertised. Confirm the minimum in the final archive and processed store build.
3. **Complete device network checks.** Check LAN permission denial/retry,
   operator-chosen HTTP/HTTPS, and reconnect/upload recovery on a real iPhone.
   Automated request and queue tests complement, rather than replace, this check.
4. **Choose the release candidate.** Decide whether to replace the pending App
   Review submission after final-build qualification. Apple approval, public app
   release, website deployment and publishing versioned artifacts are separate
   actions requiring approval. Add the App Store link only when it works publicly.
5. **Record the matched release.** Follow [Release procedure](RELEASING.md).
   Linux arm64 and prebuilt images are not claimed as validated distribution paths.
   Review historical sensor captures/build material before promoting the repository;
   do not rewrite history without authorization.

Re-run the required checks against the exact commit being published. The latest
workflow results, not old test counts in a checklist, are the evidence for a new
candidate. A hosted demo must remain synthetic and isolated from personal data.
