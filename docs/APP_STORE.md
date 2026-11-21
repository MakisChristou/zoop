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

Preparation status, not evidence of App Review approval:

- In-app privacy/support links and the retention/deletion policy are published.
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
- The isolated synthetic review server and private reviewer access are prepared.
  Five current screenshots are uploaded. Age rating, export compliance, privacy,
  wellness-device status and regional availability are saved in the store draft.
- The distribution build has been uploaded, processed and installed through
  TestFlight. The final hardware check and an actual-device demonstration video
  remain outstanding, along with the content-rights declaration.
- Keep submission and publication separately approved. TestFlight availability
  does not mean App Review approval or public availability.

## Screenshot capture

`AppStoreScreenshotTests` captures the actual Release interface with synthetic
data from `tools/layout-test-server.py`. Start that server locally, choose a
supported iPhone simulator in dark appearance, then run:

```sh
xcodebuild -project Zoop.xcodeproj -scheme Zoop -configuration Release \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' \
  -resultBundlePath /tmp/zoop-store-screens.xcresult \
  -only-testing:ZoopUITests/AppStoreScreenshotTests \
  ENABLE_TESTABILITY=YES test
```

Export the five named attachments from the result bundle. Inspect each image and
confirm its dimensions against App Store Connect's current required display size
before uploading. Retain the original screenshots; do not retouch measurements or
pretend the simulator demonstrates a connected band. The capture test checks
navigation and loaded content, not Bluetooth behavior.

References: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[ATS exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads),
[privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files).

## Publication handoff

After Apple approves the app, keep manual release selected until the owner approves
publication. Approval alone is not App Store availability.

Once the public listing is live and its download link works:

- Add the verified App Store link to the root README, website and iPhone guide.
- Make the default setup: WHOOP 5.0/MG → Zoop on iPhone → Docker Compose server.
- Remove the temporary “not on the App Store yet” notices from those pages and
  `docs/GET_STARTED.md`. Keep Xcode, signing and XcodeGen under **Build from source**.
- Retain the real server prerequisites. Docker currently builds from source;
  do not claim published images or a download-only Compose setup until validated
  release images exist. Git is optional when downloading the source ZIP.
- Check `docs/SELF_HOSTING.md`, `server/README.md`, `web/README.md` and site search
  for stale installation guidance. Preserve network, account and hardware requirements.
- Build and check the docs, verify the store link on iPhone, then publish the approved
  website update. Do not add App Store badges before the listing is available.
