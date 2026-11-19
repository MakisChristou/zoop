# Development

Start with the [setup guide](../README.md#run-it) and [repository conventions](../AGENTS.md).

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

Analysis runs in [Zoop API](https://github.com/MakisChristou/zoop-api).
Its [architecture](https://github.com/MakisChristou/zoop-api/blob/main/docs/ARCHITECTURE.md)
and [protocol](https://github.com/MakisChristou/zoop-api/blob/main/docs/PROTOCOL.md)
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
