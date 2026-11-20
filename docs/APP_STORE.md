# App Store pre-launch checks

Zoop's intended distribution includes the App Store. This is a release gate, not
an approval to submit a build. The server remains self-hosted; the listing and
onboarding must make that requirement clear.

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
  complete setup/sign-in flow. Decide and implement deletion/export behavior before
  submission; disabling an account is not deletion. Preserve the raw-data retention
  promise until that product decision is approved.
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

References: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[ATS exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads),
[privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files).
