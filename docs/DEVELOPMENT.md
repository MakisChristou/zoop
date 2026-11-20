# Development

Start with the [iPhone setup](IPHONE_SETUP.md) and [contribution guide](../CONTRIBUTING.md).

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
included loopback-only synthetic fixture server and runs loading/navigation checks.
No personal server or hardware is needed. Set `ZOOP_SIMULATOR_ID` to select a device.
Other suites use the profile and weekly-weight fixture servers under `tools/`.

Release hardening was verified with Xcode 27.2 and XcodeGen 2.46.0. Older Xcode
compatibility is not currently a release guarantee. Device signing remains local.
