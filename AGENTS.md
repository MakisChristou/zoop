# AGENTS.md

Conventions for contributors and coding agents working in Zoop. Read before changing
anything.

## Repository scope

This repository contains the iPhone app at the root, the Rust API in `server/`,
the React dashboard in `web/`, and the public website in `site/`. Read each
workspace's `AGENTS.md` for its rules. The Swift, Bluetooth, Xcode and iPhone UI instructions below
apply only to the iPhone app. Ownership, privacy and metric-parity rules apply to all.

- Run component checks from their workspace; workflows live in root `.github/`.
- Preserve existing history. Do not archive the former repositories, rewrite history,
  change visibility or activate deployments without explicit approval.
- Self-hosting is operator-managed Docker Compose. Do not bundle a TLS proxy,
  provision certificates, modify host infrastructure or choose network exposure for
  the operator. They choose Caddy, Nginx, a VPN or another access arrangement.
- Public website/docs/demo work is separate from personal installations. Demo data
  must be synthetic and must never share production credentials or a database.
- App Store distribution is part of the launch plan. Complete `docs/APP_STORE.md`
  before public launch; submitting a build still requires separate approval.
- Installation changes must pass the disposable Compose setup/isolation/restart/
  restore test in `tools/test-compose.py`. Never run it against personal data.

## iPhone app

A SwiftUI iPhone app for WHOOP 5.0 / MG straps. It owns the Bluetooth link, decodes
enough of the protocol to drive the strap, and uploads raw frames to a Zoop API server.
Analysis happens on the server; the app shows live values and sync status.

## Hard rules

- **Greenfield, independently implemented.** Other projects (NOOP, OpenStrap,
  wearable5.0, whoop-rs, Goose) are *reference material only*. Read them to understand
  the protocol, then write our own Swift. Never add them as dependencies, vendor their
  code, or copy their fixtures.
- **Pure Swift.** No Rust bridge, no third-party protocol libraries. The protocol layer
  (`Packages/ZoopProtocol`) mirrors the byte layouts documented in Zoop API's
  `server/docs/PROTOCOL.md`; when the two disagree, fix the document first.
- **Never drop frames.** Every complete frame goes to the local queue before anything
  else. Uploads are batched, retried, and removed only after a matching per-frame stored or duplicate receipt. A 2xx alone is insufficient.
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
  built by our own encoder, exactly like Zoop API's tests.
- Named constants for UUIDs, offsets and timings; no magic numbers in logic.
- Background mode `bluetooth-central` with state restoration is mandatory. Test on a
  real device.

## UI and UX

- **Flat, chart-led presentation.** Use the shared neutral black/charcoal palette,
  modest regular-weight headings, thin chart strokes and compact labels. Use colour
  for measurements and meaningful status; keep navigation and ordinary actions neutral.
  Group related readings on one surface rather than drawing a card around every value.
  Avoid gradients, glowing controls, oversized headings and decorative status banners.
- **Reference fidelity:** the adopted reference is `https://marclou.com/health`.
  Use bundled Geist via `ZoopType` (14-point medium panel titles, 11-point axes).
  Dark chart tokens: background `#0A0A0A`, surface `#171717`, muted `#A1A1A1`,
  sleep `#8194DC`, activity/steps `#479EEA`, HR/HRV/weight `#FAFAFA`.
  Cards use 20-point padding and 18-point corners; standard plots are 144 points
  plus axis labels. Use three left-axis ticks, faint horizontal dashed gridlines,
  and 2-point round lines. Avoid a dot at every sample; retain isolated samples,
  selected/latest markers, and sparse cut readings. Do not change the data to
  imitate a reference curve. Verify visual changes with actual screenshot comparisons.
- Keep five flat navigation items. Charts retain calendar paging, selection and
  accessible actions. Optional comparisons stay behind a disclosure.

- **Let clear controls explain themselves.** Do not add visible tutorial copy for
  obvious interactions, such as "Swipe to adjust" or "Tap the number to type".
  Use familiar controls, clear labels, and visual affordances instead. Keep useful
  interaction guidance in accessibility hints.
- **One fact, one place per screen.** Do not repeat a week number, status, measurement, or date in multiple badges, headings, or cards. Chart axes may provide necessary context; decorative restatements may not.
- Give each screen one clear purpose and primary action. Remove sentences that
  repeat a heading, button, picker choice, or already-visible status. Empty states
  should state what is missing briefly, with an action when one is useful.
- Show explanatory copy only when it changes a decision or is needed to complete
  the task: measurement technique, data quality, permission/privacy consequences,
  destructive actions, or error recovery. Put optional methods and technical
  details behind a named disclosure or an About screen.
- **Numbers first; explanations on demand.** Metric cards show a short label,
  value with units, and an available comparison. Do not append definitions,
  methodology paragraphs, sample-count transitions, or eligibility thresholds to
  each card. Put those behind one clearly labelled info button for the screen.
- Do not fill a missing comparison with an empty Previous column or repeated
  eligibility messages. Show the available measurement; explain missing data in
  the info view. If a status is necessary, show one short status for the screen.
- Before shipping UI copy, remove any sentence that merely narrates the UI or
  explains an obvious label. Use precise labels (e.g. "Wake-time variation") instead
  of adding a paragraph. Keep decision-critical safety, permissions and errors
  visible; this rule is not permission to hide them.
- Polish within the existing navigation and feature set unless the slice explicitly
  changes them. Prefer less clutter over extra knobs, instructions, and decoration.
- Review actual rendered screens, including a small phone and large text. Preserve
  accessible labels, hints, adjustable controls, and adequate touch targets even
  when removing visible words.

## Workflow

```sh
xcodegen generate                          # after editing project.yml
cd Packages/ZoopProtocol && swift test    # protocol tests, no device needed
xcodebuild -scheme Zoop -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Build and run on a physical iPhone that is already paired with the strap through the
official WHOOP app. Quit the official app before testing.

## When unsure

`server/docs/ARCHITECTURE.md`, `server/docs/PROTOCOL.md` and `server/docs/ROADMAP.md` are the
shared source of truth; this repo follows them.

## Metric parity

- **iPhone and web must display the same backend-owned metrics.** Use the same metric definition, source field, day/timezone and goal scope. Clients may format values, convert display units and render goal progress; they must not independently derive health metrics or substitute a different raw/filtered value. Missing data stays missing. Refresh timing may differ, but equal backend snapshots must produce equal readings.
- Displayed steps use backend walking/running-filtered counts (`steps_walking` in daily summaries, `walking` in hourly steps), never the raw strap counter. Cover source selection with regression tests when changing metric presentation.
