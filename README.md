# snoop

iPhone companion for a WHOOP MG. Holds the Bluetooth connection to the strap, pulls live
and stored data, and uploads raw frames to the self-hosted backend
[`snoop-api`](https://github.com/MakisChristou/snoop-api).

## Layout

- `rust/` — Cargo crate that depends on `snoop-ffi` from snoop-api (pinned by commit) and
  builds it as a static library.
- `scripts/build-xcframework.sh` — produces `SnoopFFI.xcframework` and Swift bindings in `Generated/`.
- `App/` — SwiftUI app: CoreBluetooth, local upload queue, live HR view.
- `project.yml` — XcodeGen spec; `xcodegen generate` writes `Snoop.xcodeproj`.

## Responsibilities, in order

1. Find the already-bonded strap (the official WHOOP app created the OS bond), connect,
   subscribe to fd4b0003/4/5/7.
2. Write `clientHello()` to fd4b0002 with response.
3. Feed every notification through `FrameReassembler`; persist complete frames to a local
   SQLite queue with a monotonic `client_seq`.
4. Drive history offload: GET_DATA_RANGE, SEND_HISTORICAL, echo cursors with `historyAck()`.
5. Upload the queue in batches to `POST /v1/ingest` with the bearer token, over Tailscale;
   delete on 2xx.
6. Show live HR and RMSSD using `decodeFrameJson()` and `rmssdMs()`.

## Build

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build-xcframework.sh
brew install xcodegen && xcodegen generate
open Snoop.xcodeproj
```

Unofficial, independent project. Not affiliated with WHOOP, Inc.
