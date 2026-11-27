# Zoop

<img src="Brand/zoop-icon.svg" width="80" height="80" alt="Zoop logo" />

**Your wearable data, on your own server.**

Zoop collects recordings from your WHOOP and keeps them on your own server.
Explore sleep, recovery, activity and weight through the iPhone app and web dashboard.
Keep the original data, export it, and rerun analysis as the software improves.

<a href="https://apps.apple.com/app/id6837762327"><img src="site/static/badges/app-store.svg" height="48" alt="Download on the App Store" /></a>

[Self-hosting](docs/SELF_HOSTING.md) · [iPhone setup](docs/IPHONE_SETUP.md) ·
[Web dashboard](web/README.md) · [Contributing](CONTRIBUTING.md)

<p align="center">
  <img src="docs/screenshots/today.png" width="195" alt="Today: sleep, recovery and load rings with daily activity" />
  <img src="docs/screenshots/sleep.png" width="195" alt="Sleep: nightly timeline, stages and comparisons" />
  <img src="docs/screenshots/activity.png" width="195" alt="Activity: recent workouts arranged on a timeline" />
  <img src="docs/screenshots/trends.png" width="195" alt="Trends: historical measurements and calendar navigation" />
</p>
<p align="center"><sub>Current app UI, captured in the simulator with sample data.</sub></p>

## Widgets for iPhone and Mac

Preview the iPhone widgets below with sample readings. On Mac, enable **Use iPhone widgets** to add them to your desktop.

**Today, Steps and Recovery** show your daily rings, step count and latest recovery score. **Weight** pairs a trend line with seven daily check-ins.

<p>
  <img src="site/static/img/widgets/today.png" width="270" alt="Sleep, recovery and load rings with a moon, heart and lightning bolt" />
  <img src="site/static/img/widgets/steps.png" width="126" alt="8,000 steps in a blue ring filled to 80 percent" />
  <img src="site/static/img/widgets/recovery.png" width="126" alt="78 percent recovery above seven daily bars" />
  <img src="site/static/img/widgets/weight.png" width="270" alt="63.8 kg with a trend line and seven check-in dots" />
</p>

**Every day** shows 20 weeks of training load, one square per day. Choose the medium **Recovery** widget for 30 days of recovery bars.

<p>
  <img src="site/static/img/widgets/every-day.png" width="338" alt="Twenty weeks of daily load squares in shades of blue" />
  <img src="site/static/img/widgets/daily-recovery.png" width="338" alt="Thirty days of green, yellow and red recovery bars" />
</p>

## What you can do

- Explore sleep stages, nightly measurements and your daily Recovery index.
- Review detected workouts, daily steps and training load.
- Track weight and cut, bulk or maintenance goals.
- Correct sleep and workouts while keeping the original recordings.
- Sync with Apple Health and export weight as CSV.
- Try manual ECG on WHOOP MG in development builds.
- Share selected charts through revocable links with optional passwords and expiry.

## Get started

You need three things:

- **Band:** WHOOP 5.0 or MG.
- **Phone:** an iPhone on iOS 26+ with Zoop installed.
- **Server:** a machine running Docker with Compose v2.

The server is required; the phone keeps an upload queue during connection outages.

```sh
git clone https://github.com/MakisChristou/zoop.git
cd zoop
./tools/setup.sh
docker compose up -d --build --wait
./tools/setup.sh --show-code
```

Open **http://localhost:8080** and create your admin account using the setup code.
Then connect the [iPhone app](docs/IPHONE_SETUP.md). See [self-hosting](docs/SELF_HOSTING.md)
for LAN access, accounts, backups and updates. Choose your own proxy or VPN.

Docker builds the server; you do not need Rust or Node installed.

## How it works

| Component | Technology | Source |
| --- | --- | --- |
| iPhone | SwiftUI, CoreBluetooth, SQLite | `App/`, `Packages/` |
| Server | Rust, PostgreSQL | `server/` |
| Web | React, TypeScript, Recharts | `web/` |
| Website and docs | Docusaurus, Markdown | [`site/`](site/README.md) |

The phone collects recordings. The server stores them and computes the metrics
shown by both clients. Accounts keep each person's data private; administrators
see operational statistics without access to other people's health records.

Health estimates are not medical diagnoses. Zoop is independently implemented
and is not affiliated with WHOOP. Public interoperability research informs the
strap protocol; other projects' protocol code is not bundled.

[Contribute](CONTRIBUTING.md) · [Report a vulnerability](SECURITY.md) · [MIT license](LICENSE)
