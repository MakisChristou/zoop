# AGENTS.md

Conventions for contributors and coding agents working in snoop. Read before changing
anything.

## What this is

A SwiftUI iPhone app for WHOOP 5.0 / MG straps. It owns the Bluetooth link, decodes
enough of the protocol to drive the strap, and uploads raw frames to a snoop-api server.
Analysis happens on the server; the app shows live values and sync status.

## Hard rules

- **Greenfield, independently implemented.** Other projects (NOOP, OpenStrap,
  wearable5.0, whoop-rs, Goose) are *reference material only*. Read them to understand
  the protocol, then write our own Swift. Never add them as dependencies, vendor their
  code, or copy their fixtures.
- **Pure Swift.** No Rust bridge, no third-party protocol libraries. The protocol layer
  (`App/Protocol`) mirrors the byte layouts documented in snoop-api's
  `docs/PROTOCOL.md`; when the two disagree, fix the document first.
- **Never drop frames.** Every complete frame goes to the local queue before anything
  else. Uploads are batched, retried, and removed from the queue only on a 2xx.
- **Respect the single bond.** The app uses the OS bond the official WHOOP app created.
  Never unpair, never attempt pairing.
- **Public project.** No personal names, team IDs, bundle-id prefixes, hosts or tokens in
  the repo. Signing lives in `Config/Local.xcconfig` (gitignored); server URL and token
  are entered in the app.
- **Conventional Commits**: `feat`, `fix`, `refactor`, `docs`, `chore`, `build`, `ci`;
  scopes `ble`, `protocol`, `queue`, `upload`, `ui`. Imperative mood, lower case, no
  trailing period. Never override the git identity.

## Code style

- Swift 5.10+, SwiftUI, Swift concurrency (`async`/`await`, actors) wherever
  CoreBluetooth's delegate API can be wrapped.
- One type per file, named after the type. Folders match the layers in the README.
- Protocol code is pure functions over `[UInt8]`/`Data`, unit-tested against frames
  built by our own encoder, exactly like snoop-api's tests.
- Named constants for UUIDs, offsets and timings; no magic numbers in logic.
- Background mode `bluetooth-central` with state restoration is mandatory. Test on a
  real device.

## Workflow

```sh
xcodegen generate      # after editing project.yml
```

Build and run on a physical iPhone that is already paired with the strap through the
official WHOOP app. Quit the official app before testing.

## When unsure

snoop-api's `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md` and `docs/ROADMAP.md` are the
shared source of truth; this repo follows them.
