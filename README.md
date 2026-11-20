# Zoop

<img src="Brand/zoop-icon.svg" width="80" height="80" alt="Zoop logo" />

**Your wearable data, on your own server.**

Zoop collects recordings from your WHOOP and keeps them on your own server.
Explore sleep, recovery, activity and weight through the iPhone app and web dashboard.
Keep the original data, export it, and rerun analysis as the software improves.

[iPhone setup](docs/IPHONE_SETUP.md) · [Server](server/README.md) ·
[Web dashboard](web/README.md) · [Contributing](CONTRIBUTING.md)

<p align="center">
  <img src="docs/screenshots/today.png" width="195" alt="Today: sleep, recovery and load rings with daily activity" />
  <img src="docs/screenshots/sleep.png" width="195" alt="Sleep: nightly timeline, stages and comparisons" />
  <img src="docs/screenshots/activity.png" width="195" alt="Activity: recent workouts arranged on a timeline" />
  <img src="docs/screenshots/trends.png" width="195" alt="Trends: historical measurements and calendar navigation" />
</p>
<p align="center"><sub>Current app UI, captured in the simulator with sample data.</sub></p>

## What you can do

- Explore sleep stages, nightly measurements and your daily Recovery index.
- Review detected workouts, daily steps and training load.
- Track weight and cut, bulk or maintenance goals.
- Correct sleep and workouts while keeping the original recordings.
- Sync with Apple Health, export weight as CSV and record ECG on WHOOP MG.
- Share selected charts through revocable links with optional passwords and expiry.

## Get started

You need a WHOOP 5.0 or MG, an iPhone on iOS 17+, and a server with PostgreSQL.
The server is required; the phone keeps an upload queue during connection outages.

1. Set up the [server and accounts](server/README.md).
2. Run the [web dashboard](web/README.md).
3. Build and connect the [iPhone app](docs/IPHONE_SETUP.md).

**Developer preview.** Installation currently requires developer tools, including
Xcode and an Apple development team with HealthKit signing support. There is no
App Store release yet. The included Compose file starts a development database;
a complete Compose installation is [planned](docs/SELF_HOSTING_PLAN.md).

## How it works

| Component | Technology | Source |
| --- | --- | --- |
| iPhone | SwiftUI, CoreBluetooth, SQLite | `App/`, `Packages/` |
| Server | Rust, PostgreSQL | `server/` |
| Web | React, TypeScript, Recharts | `web/` |

The phone collects recordings. The server stores them and computes the metrics
shown by both clients. Accounts keep each person's data private; administrators
see operational statistics without access to other people's health records.

Health estimates are not medical diagnoses. Zoop is independently implemented
and is not affiliated with WHOOP. Public interoperability research informs the
strap protocol; other projects' protocol code is not bundled.

[Contribute](CONTRIBUTING.md) · [Report a vulnerability](SECURITY.md) · [MIT license](LICENSE)
