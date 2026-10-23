# snoop

**An open companion app for WHOOP 5.0 and WHOOP MG straps.**

snoop connects to your strap over Bluetooth, pulls live and stored sensor data, and
uploads the raw frames to your own [snoop-api](https://github.com/MakisChristou/snoop-api)
server. No WHOOP account, no WHOOP cloud, no subscription.

Pure Swift. The strap protocol is implemented in the app itself.

> **Status: early development.** The app builds and implements the full pipeline
> (connect, hello, decode, queue, upload, offload acknowledgements) but has not yet been
> run against a strap. First hardware test is the next milestone; see
> [snoop-api's roadmap](https://github.com/MakisChristou/snoop-api/blob/main/docs/ROADMAP.md).

## How it works

The official WHOOP app bonds the strap to your iPhone at the OS level. snoop uses that
same bond, so there is no pairing dance. Quit the official app before using snoop: the
strap talks to one app at a time.

1. Discover the bonded strap and subscribe to the four `fd4b` notification channels.
2. Send the client hello.
3. Reassemble notifications into frames, verify both CRCs, and queue every frame locally.
4. Drive the history offload: data range, send historical, acknowledge each chunk with
   its token.
5. Upload the queue in batches to `POST /v1/ingest`; delete only on success.
6. Show live heart rate and R-R derived HRV.

## Build

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), a physical
iPhone already paired with the strap through the official app (the simulator has no
Bluetooth).

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your team and bundle id
xcodegen generate
open Snoop.xcodeproj
```

Protocol unit tests run without Xcode:

```sh
cd Packages/SnoopProtocol && swift test
```

In the app's settings, enter your snoop-api URL and bearer token.

## Repository layout

```
Packages/SnoopProtocol   format-1 framing, CRCs, record decoding, commands (pure Swift, `swift test`)
App/
  BLE/                   CoreBluetooth: discovery, connection, reconnection, state restoration, offload loop
  Queue/                 durable SQLite frame queue
  Upload/                batching, authentication, retry
  UI/                    SwiftUI views
  Settings/              server URL and token (entered in the app)
Config/                  signing settings (example committed, local copy ignored)
project.yml              XcodeGen spec
```

Conventions for contributors and coding agents are in [AGENTS.md](AGENTS.md).

## Acknowledgements

The wire protocol was understood from public interoperability research, notably the
NOOP, wearable5.0, Goose and whoop-rs projects. snoop contains no code from any of them.

## License

MIT. snoop is an independent project, not affiliated with or endorsed by WHOOP, Inc.
