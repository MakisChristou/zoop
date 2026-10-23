# AGENTS.md — snoop (iOS)

Guidance for AI agents and humans working in this repo. Read before changing anything.

## What this is

SwiftUI iPhone app for a WHOOP MG. It owns the Bluetooth link to the strap and uploads raw
frames to the self-hosted backend (`MakisChristou/snoop-api`). Decoding and analytics live
in Rust in that repo and reach Swift through UniFFI; this repo does not reimplement them.

## Hard rules

- **Swift for the app, Rust only through `snoop-ffi`.** Protocol or analytics logic belongs
  in snoop-api. If Swift needs a new capability, add it to `crates/snoop-ffi` there, bump
  the `rev` in `rust/Cargo.toml` here, and rebuild the xcframework.
- **Never drop frames.** Every complete frame goes to the local queue before anything else;
  uploads are batched, retried, and deleted only on a 2xx.
- **Respect the single bond.** The app rides the OS bond the official WHOOP app created.
  Never call `forget`/unpair APIs, never attempt pairing dances.
- **Conventional Commits**, always: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`,
  `build:`, `ci:`. Scopes: `ble`, `queue`, `upload`, `ui`, `ffi`. Imperative mood, lower
  case, no trailing period.
- **Use the developer's default git identity.** Never override author/committer.
- **No secrets in the repo.** Backend URL and bearer token come from the app's settings
  screen or an untracked `Config.local.xcconfig`.

## Code style

- Swift 5.10+, SwiftUI, Swift concurrency (`async`/`await`, actors) over callbacks where
  CoreBluetooth allows. One type per file, files named after the type.
- Layers: `App/BLE` (CoreBluetooth, reconnection, state restoration), `App/Queue` (SQLite
  frame queue), `App/Upload` (batching, auth), `App/UI` (views, view models), `App/FFI`
  (thin Swift wrappers over the generated bindings).
- Background mode `bluetooth-central` with state restoration is mandatory; test on a real
  device, the simulator has no Bluetooth.
- `Generated/` and `SnoopFFI.xcframework` are build outputs, never edited by hand.
- Prefer named constants for UUIDs and timing; they live next to the BLE layer and mirror
  `snoop_proto::gatt`.

## Workflow

```sh
./scripts/build-xcframework.sh   # after bumping the snoop-api rev
xcodegen generate                # after editing project.yml
```

Build and run on a physical iPhone that is already paired with the strap through the
official WHOOP app. Quit the official app before testing; only one app can hold the
connection at a time.

## When unsure

Check `docs/PLAN.md` in snoop-api for decisions already made; this repo follows them.
