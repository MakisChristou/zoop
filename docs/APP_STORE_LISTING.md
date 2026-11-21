# App Store listing draft

Prepared for review; nothing in this file authorizes upload or submission.

| Field | Proposed value |
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

## Review notes draft

Zoop requires a WHOOP 5.0 or MG and a self-hosted Zoop backend. The reviewer account
will connect to an isolated server containing synthetic data, allowing review of
history, charts, goals, settings and account deletion without a band. Live Bluetooth
capture requires the hardware. Supply an actual-device demonstration video with the
submission; a simulator recording alone does not demonstrate hardware behavior.

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

## Submission material still required

- Activated, isolated reviewer server; private reviewer login and review contact.
- Actual-device hardware video and final release screenshots at Apple's accepted sizes.
- Final age-rating, export-compliance and App Privacy answers reviewed by the owner.
- Non-trader declaration: owner describes this as a personal, non-commercial project;
  re-evaluate if its commercial purpose changes. Do not infer this from “free” alone.
- Distribution signing, upload validation, TestFlight and explicit submission approval.

## App Privacy worksheet

This is a data-flow inventory, **not submitted privacy labels**. Apple's collection
question depends on who can access off-device data. Normal operation sends data to
the user's chosen operator, not a central developer service. Do not automatically
select either “Data Not Collected” or “developer collects everything.” Resolve the
operator/developer distinction before completing the declaration.

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
