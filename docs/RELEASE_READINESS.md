# Release readiness

Reviewed 21 November 2026. Zoop remains a developer preview. The checks below do
not authorize publication or constitute an independent security audit.

## Verified in this installation slice

- Source-only Docker builds and a fresh Linux amd64 Compose installation: web,
  API, migrations and PostgreSQL, with only the chosen HTTP port published.
- Setup requires the operator's generated code and an empty installation. Invalid
  origins/codes, concurrent claims, oversized requests and repeated guesses are
  covered. Existing accounts, reservations or device data close setup.
- Real HTTP login through both Chromium and the API, two-account isolation, admin restrictions, restart persistence,
  backup creation and restoration into a separate empty instance. Backup overwrite
  and restore over existing tables are refused. Migrations remain idempotent.
- Rust formatting, Clippy with warnings denied, and 221 tests including PostgreSQL
  regressions; web build, formatting, 30 unit tests and 87 browser tests. The older
  fixture-specific browser/API test remains skipped; Compose has its own live HTTP
  integration test. iOS builds and five credential/address tests pass in simulator.
- Gitleaks scanned reachable history and a source-only snapshot. Two historical
  matches were verified synthetic configuration test tokens; the checked-in
  exception is restricted to that literal and those test paths. No other credential
  findings. A scanner result does not prove absence of private information.
- npm audit reported no vulnerabilities. Actionlint passed; Zizmor reported no
  unsuppressed findings. Actions are pinned and use read-only repository access.
  Dependency update configuration now covers Rust, web and Docker base images.
- The existing MIT licenses remain unchanged. App containers include Zoop's license;
  base images are pinned by multi-platform digest. No image/release was published.

## Open findings and launch gates

1. **History privacy.** Older sensor captures and generated build material remain
   in the preserved history. Review them before making the repository public. Do
   not rewrite history or replace/archive repositories without approval.
2. **Hosted material.** GitHub Actions logs/artifacts, releases, issues/PRs, wiki,
   repository visibility, branch rules and private vulnerability reporting have
   not been verified in this audit. Confirm them before publication. A repository
   checklist or local build is not evidence for hosted settings.
3. **Dependency maintenance.** RustSec flags `rsa` 0.9.10
   ([RUSTSEC-2023-0071](https://rustsec.org/advisories/RUSTSEC-2023-0071.html)) and
   `libsqlite3-sys` 0.30.1
   ([RUSTSEC-2026-0459](https://rustsec.org/advisories/RUSTSEC-2026-0459.html)) in
   the lockfile. `cargo tree --workspace --all-features --target all --invert`
   reports neither in the configured build; Zoop uses SQLx's PostgreSQL driver.
   Keep these findings visible and recheck when changing SQLx features/versions.
   `chrono` is used and has an
   [unmaintained advisory](https://rustsec.org/advisories/RUSTSEC-2026-0543.html).
   Plan its replacement with explicit date/time regression coverage. The Rust audit
   is **not clean**; it was not silenced with advisory ignores. Registry timeouts
   prevented the yanked-package check; the advisory scan completed separately.
4. **Distribution.** Validate arm64, image-layer vulnerability scans, complete
   third-party notices/SBOMs, and an upgrade from a versioned release before claiming
   a supported release. Pin app/API/web versions together. Approve release tags and
   container publication separately; no publishing credentials are needed in PR jobs.
5. **iPhone and App Store.** Physical-device HTTP/HTTPS onboarding and upload recovery
   remain to be checked for this slice. Complete [App Store checks](APP_STORE.md),
   privacy policy, account lifecycle decisions and a TestFlight review build before
   launch. Do not imply an available App Store download yet.
6. **Public presentation.** Website, docs hosting and a synthetic demo are separate
   work. Confirm support expectations and community policy before inviting outside
   contributors. Personal production is not a demo environment.

Re-run scans and release checks against the exact revision being published. This
document is a dated evidence summary, not a permanent certification.
