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
calories and steps, with the heart-rate trace underneath. The type can be changed
from the session screen; the server keeps that choice through recomputes. Nothing is
detected on the phone: after each upload the app asks the server for new sessions,
checks again one analysis interval later and whenever it returns to the foreground,
and posts a local notification per session, including "tap to label" for unlabelled
ones. With the app in the background those checks only run while iOS wakes it for
Bluetooth, so an alert can wait until the next offload or the next time you open it.

Today shows the day's sessions under the timeline, where they are shaded in their
kind's colour, and a Load tile with the day's total. Tapping the Steps tile opens a
steps screen: today by hour with every walk of three minutes or more listed, and
seven-day and thirty-day comparisons where any day opens into its own hours and walks.

Calories and zones need a body profile, entered once under Settings and stored on the
server; the phone's time zone goes with it so days are cut at local midnight.

## Repository layout

```
Packages/SnoopProtocol   format-1 framing, CRCs, record decoding, commands (pure Swift, `swift test`)
Packages/SnoopBattery    timestamped battery state and notification policy (pure Swift, `swift test`)
App/
  Activity/              session notifications after each upload
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
