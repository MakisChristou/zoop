# App Store listing

Version 1.0 build 6 was released on 24 November 2026 with owner approval.
App Store Connect shows **Ready for Distribution**. Future submissions and
releases still require approval.

| Field | Value |
| --- | --- |
| Name | Zoop: Your Health Data |
| Subtitle | Your health, on your server |
| Category | Health & Fitness |
| Price | Free |
| Language | English (UK) |
| Devices | iPhone |
| Marketing URL | https://zoop.health |
| Support URL | https://zoop.health/docs/help/ |
| Privacy URL | https://zoop.health/docs/data-privacy/ |

Keep the existing registered app identifier and signing configuration. Do not put
private signing identifiers, reviewer passwords or personal contact details here.

## Description

Zoop connects your WHOOP 5.0 or MG band to a server you control.

See your sleep, recovery, activity and weight in one place. Explore your history,
follow a weight goal and keep the original recordings on your own server.

- Sleep stages, nightly measurements and daily recovery
- Detected workouts, steps and training load
- Weight tracking with cut, bulk and maintenance goals
- Optional Apple Health imports and exports
- A companion web dashboard with optional, revocable sharing links

You need a compatible band and a running Zoop server. Zoop does not provide a
hosted health-data service. Setup instructions are available at zoop.health.

Zoop is an independent open-source project, not affiliated with WHOOP.
Measurements and scores are estimates for general wellness, not medical diagnoses.

## Keywords

sleep,recovery,fitness,weight,steps,self-hosted,health,activity,training

## Review notes summary

Zoop requires a WHOOP 5.0 or MG and a self-hosted Zoop backend. The reviewer account
connects to an isolated server containing synthetic data, allowing review of
history, charts, goals, settings and account deletion without a band. Live Bluetooth
capture requires the hardware. The private submission includes an actual-device
video recorded with build 3; the notes explain that build 6 retains the connection
workflow. A simulator recording alone does not demonstrate hardware behavior.

The release excludes manual ECG. It does not include a VO₂ max, biological-age or
blood-pressure estimate. It uses no advertising, tracking SDK or in-app purchases.

The app allows user-selected HTTP servers for trusted LAN/VPN installations through
its ATS exception. HTTPS retains the system certificate checks; credential-bearing
requests do not follow redirects. Review access should use trusted HTTPS.

Apple Health access is optional. Declining it does not prevent Bluetooth capture or
viewing server data. Permissions are requested when connecting Apple Health.

Account deletion is under Profile & settings → Account → Delete account and
requires the password. It erases owned server records and revokes sessions/shares.
The last administrator must assign another enabled administrator first. Operator
backups and copies deliberately exported to Apple Health or files are separate.

## Saved submission information

- Isolated synthetic reviewer server and private review login/contact.
- Actual-device hardware video and five iPhone screenshots.
- Owner-approved age rating (9+), OS-only encryption answer and App Privacy label.
- Non-trader declaration for this personal, non-commercial project; re-evaluate if
  its commercial purpose changes. Do not infer this from “free” alone.
- Free distribution in all selected regions except China mainland (174 regions).
- General wellness; declared not a regulated medical device and no third-party content.
- Distribution signing, upload validation, TestFlight and Apple approval completed.

## App Privacy

The owner approved and published **Data Not Collected** for developer collection.
Normal operation sends data to the user's chosen operator, not a central developer
service. Reassess the declaration if that model changes. The inventory below
records destinations; it does not mean the app keeps all data on the phone.

| Data | Destination and purpose |
| --- | --- |
| Health and fitness readings, raw band recordings | Chosen server; storage and analysis |
| Imported Apple Health weight | Chosen server when the user enables import |
| Email/account ID, band serial | Chosen server; authentication and ownership |
| Optional profile photo | Chosen server; profile display |
| Selected public chart values | People with an enabled share link |
| Diagnostics and request logs | Operator-controlled logs; operational support |

No ad tracking, third-party analytics SDK or sale of health data is implemented.
A reviewer demo operated by the project must prohibit real uploads or clearly
separate them from synthetic access; it must not silently become a hosted service.
