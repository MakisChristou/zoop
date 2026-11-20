# Zoop

<img src="Brand/zoop-icon.svg" width="80" height="80" alt="Zoop logo" />

**Your wearable data, on your own server.**

Zoop is an independent iPhone app for WHOOP 5.0 and WHOOP MG. Track sleep,
activity, weight and long-term trends with software you can inspect and host yourself.
The phone collects your recordings; [Zoop API](https://github.com/MakisChristou/zoop-api)
keeps your history and runs the analysis.

[iPhone](https://github.com/MakisChristou/zoop) ·
[API](https://github.com/MakisChristou/zoop-api) ·
[Web dashboard](https://github.com/MakisChristou/zoop-web)

<p align="center">
  <img src="docs/screenshots/today.png" width="195" alt="Today: sleep, steps and load rings with daily activity" />
  <img src="docs/screenshots/sleep.png" width="195" alt="Sleep: nightly timeline, stages and comparisons" />
  <img src="docs/screenshots/activity.png" width="195" alt="Activity: recent workouts arranged on a timeline" />
  <img src="docs/screenshots/trends.png" width="195" alt="Trends: historical measurements and calendar navigation" />
</p>
<p align="center"><sub>Current app UI, captured in the simulator with sample data.</sub></p>

## What you can do

- Explore sleep stages, nightly measurements and comparisons with your usual nights.
- Review detected walks and strength sessions, daily steps and training load.
- Log weight and follow cut, bulk or maintenance goals with a weekly outlook.
- Correct sleep and workouts without losing the original recordings.
- Sync with Apple Health, export weight as CSV and record ECG on WHOOP MG.

**Developer preview.** Build from source; there is no App Store release yet.
Health estimates and ECG recording are experimental, not medical diagnoses.
Zoop is not affiliated with WHOOP.

## Run it

You need a WHOOP 5.0 or MG, an iPhone on iOS 17+, and your own
[Zoop API server](https://github.com/MakisChristou/zoop-api). Build with Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen); the verified toolchain is
Xcode 27.2 / XcodeGen 2.46.0. Device builds need an Apple development team with
HealthKit signing support.

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
4. Enter your server's HTTPS URL and sign in with an account created by its administrator.

Pair the strap in the official WHOOP app first, then quit that app before connecting
with Zoop. Keep the existing Bluetooth bond. A simulator can preview the interface,
but cannot collect strap data.

## How it works

**SwiftUI · CoreBluetooth · SQLite · Swift Charts**

The app saves sensor frames locally before uploading them and retries until the
server confirms receipt. Analysis runs in Rust on your server, with PostgreSQL
holding the original recordings and derived history. The iPhone and web dashboard
use the same backend metrics; live Bluetooth readings stay on the phone.

A backend is required. The local queue protects collection during connection
outages; it is not a standalone offline analytics mode. Keeping the original data
lets you back it up and rerun improved analysis later, while preserving corrections.

## Contribute

Start with [development and tests](docs/DEVELOPMENT.md),
[contributing](CONTRIBUTING.md) and the [visual style guide](docs/VISUAL_STYLE.md).
Report vulnerabilities through [SECURITY.md](SECURITY.md).

The strap protocol is independently implemented, informed by public interoperability
research from NOOP, wearable5.0, Goose and whoop-rs. Their code is not bundled.

[MIT license](LICENSE).
