# Development

Start with the [contribution guide](../CONTRIBUTING.md). These instructions are for
working on Zoop's code; regular setup is in the [iPhone guide](IPHONE_SETUP.md).

## Build the iPhone app from source

You need a Mac, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple
development team with HealthKit signing support. The verified toolchain is
Xcode 27.2 / XcodeGen 2.46.0.

```sh
git clone https://github.com/MakisChristou/zoop.git
cd zoop
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

1. Set your development team and a unique bundle ID in `Config/Local.xcconfig`.
   This file is ignored by Git.
2. Generate and open the project:

   ```sh
   xcodegen generate
   open Zoop.xcodeproj
   ```

3. Select the **Zoop** scheme and your iPhone, then Run.
4. [Connect to your server](IPHONE_SETUP.md#connect-to-your-server).

A simulator can preview the interface, but cannot collect band data.

## Code layout

| Path | Purpose |
| --- | --- |
| `App/UI` | SwiftUI screens and charts |
| `App/BLE` | Strap connection, restoration and history offload |
| `App/API` | Server requests and app data integration |
| `Packages/ZoopProtocol` | Framing, CRCs, commands and record decoding |
| `Packages/ZoopSync` | Durable queue and upload receipts |
| `Packages/ZoopData` | Shared data models and transformations |
| `Packages/ZoopHealth` | Health sync and weight policies |
| `Packages/ZoopBattery` | Battery state and notification policy |
| `Packages/ZoopECG` | ECG capture state and validation |
| `Config` | Shared settings and ignored local signing configuration |
| `project.yml` | XcodeGen project definition |

Analysis runs in [Zoop API](../server/README.md).
Its [architecture](../server/docs/ARCHITECTURE.md)
and [protocol](../server/docs/PROTOCOL.md)
documents describe the shared system.

## Checks

Run the Swift package tests:

```sh
for package in ZoopProtocol ZoopSync ZoopBattery ZoopHealth ZoopData ZoopECG; do
  swift test --package-path "Packages/$package"
done
```

Generate the project after changing `project.yml`, then build without device signing:

```sh
xcodegen generate
xcodebuild -scheme Zoop -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Run app tests on an available simulator (substitute its name):

```sh
xcodebuild -scheme Zoop \
  -destination 'platform=iOS Simulator,name=<simulator name>' \
  CODE_SIGNING_ALLOWED=NO -only-testing:ZoopTests test
```

The [CI workflow](../.github/workflows/ios.yml) defines the automated checks.
Bluetooth, background delivery and real ECG capture also need physical-device testing.
Keep recordings, screenshots, credentials and local signing settings out of commits.

## Further reading

- [Visual style](VISUAL_STYLE.md): shared typography, colours and chart conventions.
- [Performance](PERFORMANCE.md): concurrency, regression checks and UI fixtures.

## Reproducible UI checks

Run `bash tools/test-ui.sh` after generating the project. It starts and stops the
included loopback-only synthetic fixture servers and runs loading, navigation, goal
history and accessible weight-entry checks.
No personal server or hardware is needed. Set `ZOOP_SIMULATOR_ID` to select a device.
Other suites use the profile and weekly-weight fixture servers under `tools/`.

Release hardening was verified with Xcode 27.2 and XcodeGen 2.46.0. Older Xcode
compatibility is not currently a release guarantee. CI pins Xcode 26.6 with the
iOS 26.5 simulator rather than relying on the runner’s default Xcode. Device signing
remains local.

### Setup preview

Open **Profile → Preview setup** to walk through the first-run screens with sample
connection states. This does not sign out, reset onboarding, scan for a band or
modify stored recordings. Closing or finishing the preview returns to Profile.
Do not reset the onboarding preference on a phone to test setup.

`SetupFlowTests` checks preview isolation and first-run transitions. `SetupUITests`
checks the four screens, cancellation, large text and signing in without restarting
the wizard, using the synthetic fixture server. Real Bluetooth permissions and
connection still need a separate physical-device check.
