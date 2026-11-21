# App Store pre-launch checks

Zoop's intended distribution includes the App Store. This is a release gate, not
an approval to submit a build. The server remains self-hosted; the listing and
onboarding must make that requirement clear.

The initial store release targets iPhone. Manual ECG is enabled only in Debug
builds through `BuildFeatures.manualECG`. Release builds hide its entry points,
block recording, and cancel ECG reminders, while preserving existing recordings
and pending device-cleanup recovery. Do not enable it for distribution until its
measurement validation and release scope have been reviewed.

`App/PrivacyInfo.xcprivacy` declares
app-local preferences (`CA92.1`) and elapsed-time measurements for ECG capture
(`35F9.1`). It does not replace the privacy policy or App Store privacy answers.
Review these declarations whenever storage, timing or third-party dependencies
change, and check that the manifest is present in the archived app.

- **Networking:** verify login and uploads on a real iPhone over LAN HTTP, VPN and
  trusted HTTPS, including local-network permission denial and recovery. The app
  uses `NSAllowsArbitraryLoads` because users choose servers that cannot be known at
  build time. Prepare that justification for App Review; acceptance is not guaranteed.
  Keep normal TLS certificate checks and prevent credential-bearing redirects.
- **Privacy:** publish an accurate policy and App Store privacy answers covering
  Bluetooth recordings, HealthKit, photos, account identifiers, the user's chosen
  server, optional public links and retention. Review privacy manifests and required
  reason APIs against the actual release binary and dependencies.
- **Account lifecycle:** review Apple's account-deletion requirements against the
  complete setup/sign-in flow. Password-confirmed deletion is implemented; verify it
  against the deployed review server before submission. Disabling an account is not
  deletion. Raw retention otherwise remains unchanged.
- **Health claims:** review Recovery, sleep, ECG and other estimates, their methods,
  consent and labels. Do not present them as clinical diagnoses or a certified
  replacement for medical equipment. Verify HealthKit reads/writes and permissions.
- **Review access:** provide a separate synthetic demo server/account and explain
  the compatible hardware requirement. Never give reviewers personal production
  credentials or recordings. Test first-run, no-band, denied-permission and offline
  upload-queue behavior.
- **Release:** confirm bundle identifier, signing, entitlements, privacy/support
  URLs, screenshots, accessibility and supported device/OS coverage. Validate an
  archive and TestFlight build before requesting approval for App Store submission.

## Release preparation (21 November 2026)

These are remaining release tasks, not evidence of App Review approval:

- In-app privacy/support links and a full retention/deletion policy are prepared.
  Publish the updated policy before submission; a local edit is not a live policy.
- Password-confirmed account deletion is implemented with owner isolation, last-admin
  protection and concurrency fences. Deploy the matching API before distributing the
  app. Other installations must upgrade to offer deletion.
- Health storage, raw queues, ECG files and cached summaries in Preferences are marked
  for backup exclusion. Existing local records remain intact; past backups are not erased.
- Free Health & Fitness, English and the existing app identifier are approved. Listing
  text and privacy inventory are in [APP_STORE_LISTING.md](APP_STORE_LISTING.md).
- Manual ECG states that waveform timing and amplitude are uncalibrated and is
  excluded from Release builds. Recovery and
  other estimates need evidence-backed methodology, not diagnostic claims.
- The release needs a synthetic review account/backend, an actual-device video
  demonstrating the band, current screenshots, age-rating answers, export
  compliance answers and completed App Store privacy declarations.
- A development-signed archive is not an App Store distribution build. Complete
  distribution signing, Apple's upload validation and TestFlight checks before
  declaring the binary ready. Keep submission and publication separately approved.

References: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[ATS exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads),
[privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files).
