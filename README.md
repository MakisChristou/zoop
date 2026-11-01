# snoop

**An open companion app for WHOOP 5.0 and WHOOP MG straps.**

snoop connects to your strap over Bluetooth, pulls live and stored sensor data, and
uploads the raw frames to your own [snoop-api](https://github.com/MakisChristou/snoop-api)
server. No WHOOP account, no WHOOP cloud, no subscription.

Pure Swift. The strap protocol is implemented in the app itself.

> **Status: early development.** The app has been exercised with a real strap;
> protocol coverage and background behavior still need continued hardware testing.
> See [snoop-api's roadmap](https://github.com/MakisChristou/snoop-api/blob/main/docs/ROADMAP.md).

## How it works

The official WHOOP app bonds the strap to your iPhone at the OS level. snoop uses that
same bond, so there is no pairing dance. Quit the official app before using snoop: the
strap talks to one app at a time.

1. Discover the bonded strap and subscribe to the four `fd4b` notification channels.
2. Send the client hello.
3. Reassemble notifications into frames, verify both CRCs, and queue every frame locally.
4. Drive the history offload: data range, send historical, acknowledge each chunk with
   its token.
5. Upload to `POST /v2/ingest`; remove only frames with matching stored or duplicate receipts.
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

Enter your snoop-api URL and bearer token during setup, or later under Profile → Advanced.

## Navigation

Five tabs: Today, Activity, Sleep, Trends and Battery. Every tab shows the strap's
connection state in its header and a profile button that opens a sheet with the body
profile, the device page (strap identity, history sync, the raw latest record), the
notification permission, and, under Advanced, the server connection and upload
diagnostics. Today keeps the overview; the Steps tile opens steps by hour and by day,
and a banner at the top says what to do whenever the strap is not connected.

## Battery

The Battery tab shows separate strap and pack percentages, charging animations,
and reminders to recharge either battery. Pack readings come from live WHOOP 5/MG
event 109. Command 151 provides a cached fallback when supported; cached readings
never trigger notifications. Disconnecting or removing the pack ends its live state.
Snoop asks for notification permission once, after setup. Alerts are enabled by
default at 20%, 10% and 5%, at 100%, and after removing the pack. Change notification
permission in iOS Settings.

These are local iOS notifications driven by fresh Bluetooth readings, including
background Bluetooth updates. Replayed history cannot trigger alerts. Keep Bluetooth
on and do not force-quit Snoop if you want background reminders. Charging status uses
the strap's charger-on/off events. After reconnecting mid-charge, sustained rising
readings can also detect charging; the screen labels this inference. Query and event
readings are compared separately to avoid rounding artifacts. The tab shows both
batteries and power flowing from pack to strap, with green above 20%, yellow at
6–20%, and red at 5% or below. The pack keeps a grey last-known level when detached
or stale. Its level changes indicate charging or discharging; presence alone does
not establish power flow. Pack events carry tenths of a percent, corroborated by
our recorded MG charging sessions. Pack alerts use the same 20/10/5 and 100% policy;
no pack alerts are possible while it is disconnected and not reporting through
the strap. Battery level is queried when connecting and every 30 seconds while
viewing Battery. A rejected pack query stops until reconnect; pushed events continue.

Battery policy tests run independently:

```sh
cd Packages/SnoopBattery && swift test
```

## Activity

The Activity tab lists sessions the server detects: walks of ten minutes or more,
resistance training of twenty minutes or more, and anything else that raised heart
rate for twenty minutes, left unlabelled for you to name. Each session shows its
load on a 0–21 scale, time in five heart-rate zones, average and peak heart rate,
calories and steps, with the heart-rate trace underneath. The session menu edits type and times, merges neighbouring sessions including rests,
splits a session, removes a false detection, or undoes the last correction. Editing
starts from an existing detected workout, with its current times prefilled. Removed
workouts can be restored from Activity. The server preserves corrections through recomputes. Nothing is
detected on the phone: after each upload the app asks the server for new sessions,
checks again one analysis interval later and whenever it returns to the foreground,
and posts a local notification per session, including "tap to label" for unlabelled
ones. With the app in the background those checks only run while iOS wakes it for
Bluetooth, so an alert can wait until the next offload or the next time you open it.

Today’s arrows select a calendar day; the heading follows that day, and Back to today
returns to the live view. Steps, Sleep and Activity links retain the selected date.
Today shows the day’s sessions and a timeline, where they are shaded in their
kind's colour, and a Load tile with the day's total. Tapping the Steps tile opens a
steps screen: today by hour with every walk of three minutes or more listed, and
seven-day and thirty-day comparisons where any day opens into its own hours and walks.

Calories and zones need a body profile, entered once under Settings and stored on the
server; the phone's time zone goes with it so days are cut at local midnight.

## Repository layout

```
Packages/SnoopProtocol   format-1 framing, CRCs, record decoding, commands (pure Swift, `swift test`)
Packages/SnoopSync       durable SQLite queue, ordered persistence, upload receipts and retries
Packages/SnoopBattery    timestamped battery state and notification policy (pure Swift, `swift test`)
App/
  Activity/              shared workout state, correction commands and session notifications
  Battery/               iOS notifications and persisted per-strap alert state
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

## Reliable history

Complete frames pass through a serial persistence barrier before live decoding or
history acknowledgements. SQLite uses WAL and full durability. If storage fails,
history acknowledgements pause; queued callbacks resume in order after a successful
retry, and the strap is asked to replay history. Do not delete the app to repair a
queue: uninstalling also removes its saved frames.

Each new frame has a persisted UUID. Existing queue rows keep their original
sequence identity during migration. The uploader requires a matching v2 receipt for
every submitted row. A lost or malformed response retains the whole batch; rejected
or conflicting rows remain saved separately while healthy rows continue. Diagnostics
shows held frames and provides a retry action. There is no fallback to aggregate v1
acknowledgements; deploy a backend supporting v2 before installing this app.

History processing is server-side and survives app/service restarts. Diagnostics
shows pending decode and analysis work separately. Historical backfill sessions are
silent; only server-eligible recent sessions can trigger a notification. iOS still
controls when background Bluetooth work runs, so continuous processing on the phone
is not guaranteed while the OS has suspended it.

Run the failure-path tests with:

```sh
swift test --package-path Packages/SnoopSync
```

## Correction validation

The backend must include migration 0008 and the sleep/reset correction endpoints before this app
is installed. Saving uses an idempotent request and the session revision; unsuccessful
saves retain the form. Scores stay blank while updated metrics are pending. Partial
recordings are marked, and corrections/recalculations do not send detection alerts.

Simulator UI checks in `UITests` use the synthetic `UI-REVIEW` strap and an isolated
backend, never a real device or production database. The default test URL is
`http://127.0.0.1:28472` (a local tunnel to the test server), with the development-only
`ui-test-token`. `SNOOP_UI_SERVER_URL` can override the URL in the test runner.
Seed an isolated database with `tools/ui-fixture.sql` from the backend repository,
start its worker, then run:

```sh
xcodegen generate
xcodebuild -scheme Snoop -destination 'platform=iOS Simulator,name=Snoop UI Review' test
```

The tests verify selected-day navigation and editing/merge/split/remove/restore.
Reset the isolated fixture between full runs; the correction test changes
its synthetic sessions. Real-device walk/gym validation remains separate.

### Sleep corrections and resetting history

Sleep includes every local wake-up date, with naps available throughout the day.
Use a detected recording’s menu to correct its Fell asleep / Woke up times,
change Main sleep / Nap, merge, remove, or undo. Sleep and workout editors require
an existing recording; the app does not offer manual creation.
Saved readings are required. Missing periods remain gaps and awake breaks remain
awake; editing the sleep period does not label every minute as sleep. Removed
sleep can be restored from the Sleep screen.

Reset to automatic is available in a recording’s menu and in Profile & settings →
Advanced. Choose sleep, workouts, or both, for a date range or all recorded history.
Review the affected dates before confirming: linked edits can expand the range.
Reset clears the chosen manual overrides, keeps recordings, and rebuilds results.
Recent resets remain undoable after reopening the app; a conflicting newer edit
must be undone first. Ordinary background recalculation preserves manual edits.
Sleep, Today, Trends and dependent workout metrics refresh without detection alerts.

The simulator suite also exercises sleep editing/merging and reset/undo. It uses
only the synthetic backend fixture. Device validation uses a
normal signed install and launch; screen mirroring and a physical debugger are not
needed to test these features.

## Morning insights

Today’s Morning brief opens personal sleep, HRV and resting-heart-rate comparisons,
with a weekly summary and sleep timing variation. It follows the selected date.
Seven usable prior readings allow an early baseline; fourteen allow a usual range.
Incomplete recordings, learning and recalculation remain explicit. The API owns the
calculations; corrections, Reset and Undo refresh the results. Methods are available
from the information button. No new notification permission or setup is required.

`MorningInsightsTests` exercises the brief, detail, method sheet, historical navigation
and large text using the synthetic `INSIGHT-REVIEW` fixture on a development API.
Set `SNOOP_UI_SERVER_URL` for that API; the default test loopback port is 28473.
