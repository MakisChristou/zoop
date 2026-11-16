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

Five tabs: Today, Activity, Sleep, Trends and Goals. Every tab shows the strap's
connection state in its header and a profile button that opens a sheet with the body
profile, the device page (strap identity, history sync, the raw latest record), the
notification settings, and, under Advanced, the server connection and upload
diagnostics. Today keeps the overview; the Steps tile opens steps by hour and by day,
and a banner at the top says what to do whenever the strap is not connected.

## Battery

My WHOOP, opened from the connection status or Profile, shows strap and pack percentages, charging animations,
and reminders to recharge either battery. Pack readings come from live WHOOP 5/MG
event 109. Command 151 provides a cached fallback when supported; cached readings
never trigger notifications. Disconnecting or removing the pack ends its live state.
Snoop asks for notification permission once, after setup. Alerts are enabled by
default at 20%, 10% and 5%, at 100%, and after removing the pack. Change notification
preferences in Profile → Notifications, with a link to iPhone notification settings.

These are local iOS notifications driven by fresh Bluetooth readings, including
background Bluetooth updates. Replayed history cannot trigger alerts. Keep Bluetooth
on and do not force-quit Snoop if you want background reminders. Charging status uses
the strap's charger-on/off events. After reconnecting mid-charge, sustained rising
readings can also detect charging; the screen labels this inference. Query and event
readings are compared separately to avoid rounding artifacts. The page shows both
batteries and power flowing from pack to strap, with green above 20%, yellow at
6–20%, and red at 5% or below. The pack keeps a grey last-known level when detached
or stale. Its level changes indicate charging or discharging; presence alone does
not establish power flow. Pack events carry tenths of a percent, corroborated by
our recorded MG charging sessions. Pack alerts use the same 20/10/5 and 100% policy;
no pack alerts are possible while it is disconnected and not reporting through
the strap. Battery level is queried when connecting and every 30 seconds while
viewing My WHOOP. A rejected pack query stops until reconnect; pushed events continue.

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

## Calendar charts and daily details

Trends and Morning insights share calendar Week, Month, 3 months (calendar quarter),
and Year pages. Swipe horizontally to change a period; tap or hold and drag to
inspect an actual reading. Previous/next buttons and VoiceOver actions provide the
same navigation. Returning from a reading keeps the selected date and page.
Calendar arithmetic respects locale week starts, time zones and daylight saving.
History is prepared off the main executor; switching or paging does not fetch it
again. Missing days break lines, and sleep readouts use hours and minutes.

The eight-week sleep heatmap opens a themed summary and the complete sleep record.
Typical weekday comparisons stay inside Comparisons and appear only after at least
two readings for every weekday within the past eight weeks. Learning detail uses
one chart selected by its three metric cards, opening on the selected week; baseline and weekly details remain
inside the chart disclosure.

Today restores the seven weigh-in circles and puts live heart rate inside the daily
timeline. Battery, including both pack and strap, lives under Profile → My WHOOP;
the header shortcut and battery notifications open that page. The five tabs are
Today, Activity, Sleep, Trends and Goals.

Sleep uses one local comparison snapshot for all metrics, including resting HR,
HRV, time asleep and stage durations. It does not depend on the separate Morning
insights request or its revision. Each metric requires seven distinct eligible main
sleeps within the preceding 28 local calendar days. The selected day and future
nights are excluded. The latest revision wins before filtering missing/pending
measurements or recordings with over 120 seconds of unknown data. Calculations
never alter stored sleep data or the Morning outlook assessment.

Resting HR comparisons use bpm; temperature uses °C. Other comparisons use relative
percentages. Higher resting HR, awake time and disturbance counts are red; lower is
green. HRV and efficiency use the opposite direction. Stage durations, time asleep,
temperature, breathing and oxygen stay neutral because direction alone does not
establish a better night. Zero changes remain visible and neutral; missing data or
a positive value over a zero percentage baseline does not invent a comparison.

Every metric card reserves its own comparison line below the reading. Cards align
within each row and collapse to one column at accessibility text sizes. Recording
coverage is a compact footer. The stage summary shows REM/deep/light; estimated
wake segments remain in the hypnogram rather than presenting a competing total
alongside the window-based Awake metric. The hypnogram, correction menu, awakenings, naps and removed-sleep
navigation remain available.

## Focused layout validation

Today keeps the morning assessment and weight check-in compact. In Trends and
Morning insights, comparison statistics remain available through disclosures.
Weight entry and profile height support a scrolling ruler, numeric typing, and
VoiceOver adjustment. Height edits remain part of the profile draft until Save
profile; weight still requires Save weight. No analysis or sync rules change.

Run `python3 tools/layout-test-server.py` for generated, loopback-only history on
port 28476. It accepts in-memory test weigh-ins and never contacts a real backend.
Use a clean simulator install when switching from another fixture namespace.

```sh
xcodegen generate
TEST_RUNNER_SNOOP_UI_SERVER_URL=http://127.0.0.1:28476 xcodebuild \
  -scheme Snoop -destination 'platform=iOS Simulator,name=Snoop UI Review' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:SnoopTests -only-testing:SnoopUITests/CalendarNavigationTests \
  -only-testing:SnoopUITests/LayoutPolishTests \
  -only-testing:SnoopUITests/MeasurementEntryTests \
  -only-testing:SnoopUITests/HealthWeightTests \
  -only-testing:SnoopUITests/TrendSelectionTests \
  -only-testing:SnoopUITests/MorningInsightsTests test
```

These checks cover vertical scrolling over charts, horizontal paging and held
inspection, heatmap accessibility values, comparison disclosures, centered date
navigation, ruler/keyboard entry, cancel semantics, and large-text reachability.
Review light appearance and a small-screen simulator too. Physical screenshots
and test result bundles belong outside the repository.

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

The brief and detail refresh independently of the other Today feeds. While visible
and foregrounded they recheck recalculation every five seconds, awaiting-sync every
30 seconds, errors every 15 seconds and settled results every five minutes. Returning
to the screen refreshes immediately; an upload or correction that returns Updating
interrupts a longer settled wait. Failed requests replace stale Updating with Retry.
Date, device and connection changes fence off older requests.

`MorningInsightsStoreTests` covers refresh, retry, cancellation and stale results.
For the automatic screen transition test, run `python3 tools/morning-refresh-server.py`
and then the `SnoopUITests/MorningRefreshTests` test on a simulator. Its loopback API
on port 28479 returns Updating for eight seconds and then Learning, while unrelated
Today endpoints fail. It uses synthetic data and does not require a backend database.

Morning outlook uses a neutral Headline card above the daily overview. Only its
status and individual comparison deltas carry green, amber or red. The backend
supplies the classification; mixed signals stay mixed and incomplete/early data
stays neutral. Details and the method sheet explain the comparisons. This is a
descriptive outlook, not a validated readiness score or a training recommendation.

## Apple Health and weight

Today’s Quiet check-in offers a direct Log button until a weight is recorded for the
local day, then shows a completed state. Apple Health readings count too. The weekly
row counts recorded days, never the direction of weight change. Tapping the card
opens Weight; entry is seeded with the latest reading and still requires Save.

Weight uses calendar Week/Month/3 months/All pages. Weeks follow the device calendar;
months start on the first, and three-month pages contain three complete months.
Swipe to the previous/next period, tap a recorded point, or hold then drag to inspect
readings without paging. Latest returns to the current period. Raw measurements
remain the default; an optional 7-day moving average lives in Weight options.
Health readings take priority over Snoop readings on the same date, with all distinct
Health readings retained. Missing days are never zero-filled and gaps of a week or
more break the line. The chart stays focused on measurements; Weight options contains All weigh-ins
and Import weight history. Weekly check-in circles remain on Today.

Apple Health connection and export controls remain in Profile & settings. Connecting
asks for sleep and workout write access, optional steps/weight export and optional
weight import. Automatic sharing starts at connection time. Weight → options → Import weight
history previews Health readings automatically with All available history enabled;
turning it off reveals a date range.
It imports only weights, reports existing readings separately, and never enrolls
sleep/workout/steps exports. Export older Snoop history is a separate consent action
in Apple Health settings. Legacy combined selections retain both original consents;
new selections are stored separately. Imports resume from saved per-reading receipts
and overlapping ranges reuse stable identities.

Sleep exports actual known asleep intervals, including naps, without guessed sleep
stages, awake breaks or missing seconds. Workouts export corrected type, times and
continuous duration. Steps use timed minute counts with the same walking/running
filter as the dashboard; Health controls priority relative to phone/watch sources.
Calories, heart measurements, readiness, and sleep/workout imports are not included.
The server maintains a separate transactional export feed; editing, merging,
splitting, removal, reset and undo do not depend on detector version numbers.

Weight entries are saved durably on the phone before upload, with kg/lb entry,
history of actual measurements. Imported readings
retain their date, identity and source and are read-only in Snoop. A visible external
weight takes precedence in the daily summary; imported values are never re-exported.
The profile follows the newest actual weigh-in by local date, with Apple Health
preferred within that day. The weight row opens Weight and refreshes after sync;
editing other profile fields cannot overwrite a measured weight. A manual profile
weight is only a fallback before measurements exist. Historical imports cannot move
current weight backward, and historical analytics use measurements before that day's
end. No measurements are invented for missing days.

Once a day has a reading, the Weight screen hides Log weight. Tap the displayed
weight or a history value to edit that Snoop measurement; imported Health readings
show their source and remain read-only. Every local save checks the selected
calendar day, including entries still waiting to upload, and rejects a second
entry or a move onto an occupied day. Existing imported history is preserved.

Weight has a direct Import weight history action below its recent readings, also
available in Apple Health settings and Weight options. Import remains available
after an earlier import; the preview skips readings already saved.

Weight → options → Export CSV shares all non-deleted weigh-ins currently saved on
the phone, including imported measurements and entries waiting to upload. It is
independent of the chart range and display unit: each observation keeps its UTC
timestamp, date in the export time zone, kilograms, source and reading ID. It does
not average or collapse multiple readings on a day, or change Health records.

Profile photos can be chosen, replaced or removed from the profile header. The native
Photos picker shares only the selected image; the app downsamples to at most 512 px,
applies orientation and strips source metadata before upload. A protected Postgres
endpoint stores one small JPEG per profile, with a scoped on-device cache for offline
display. Failed uploads keep the old photo and the draft available for retry.
`ProfilePhotoTests` covers image preparation, cache persistence, failure and scope
isolation. `ProfileUITests` uses `python3 tools/profile-test-server.py` on loopback
port 28480 for profile, import and native-picker navigation, including large text.


Weight export skips visible existing external measurements on the same local date.
If another source arrives later, Snoop removes only its own redundant Health copy.
HealthKit does not disclose read-permission denial: an empty query cannot prove an
empty day. The connection screen therefore makes weight export an explicit opt-in
and does not promise cross-app deduplication. Pause and disconnect preserve existing
Health data. Removing Snoop exports is a separate confirmed action scoped to the
selected backend dataset; other sources and the Snoop server history are untouched.
Health consent and progress live in a protected, backup-excluded local journal.

Daily check-ins use local notifications configured in Profile → Notifications.
Weigh-in defaults to 09:00 and preserves the previous reminder on/off preference;
ECG is opt-in, defaulting to 20:00. No wake analysis or network round-trip is needed
to deliver an already scheduled reminder. Times use the phone's local calendar.
A known weigh-in cancels that day's weight request, including visible Apple Health
measurements; a saved ECG with samples cancels that day's ECG request. Changes from
other apps can only cancel a reminder after Snoop observes them. Locked Health
storage can delay this, and HealthKit does not disclose denied read access.

The app maintains 28 days of one-shot requests (at most 56 across both check-ins),
refreshed on app/background activity, settings changes and significant time changes.
Without another app wake, reminders stop when that horizon expires. Completion,
disabling reminders, and account changes reconcile pending requests. Old wake-based
requests are removed. Scheduled-at receipts prevent a second same-day reminder if
the time is moved after it was due; they do not prove delivery. There is no late
catch-up when opening Snoop after the selected time. Taps open the weight entry or
ECG page, including after a cold launch. iOS permission, Focus and notification
settings still govern presentation; there is no APNs service or guaranteed delivery.

Battery alerts remain driven by fresh live device readings and can be disabled in
Notifications. The off-body implementation waits ten minutes after a fresh live
removal event, cancels on reattachment or loss of continuity, and alerts once per
removal. It never uses missing heart rate, rest/motion, or disconnection as removal
evidence. Off-body reminders are enabled by default and can be switched off in
Profile → Notifications. Live removal (code 10) and reattachment (code 9) events
have been observed on MG hardware. Historical uploads do not start a timer, and
reconnecting or restarting requires a new live removal event. A real ten-minute
notification delivery check remains separate from signal and automated tests.

Deploy backend migration 0009 before installing this app. HealthKit and background
Health delivery require an enabled App ID, suitable provisioning profile, and current
Apple Developer agreements. On-device acceptance must verify permissions, actual
Health entries, edits/removals, backfill repetition and a real scheduled reminder.
Simulator UI tests and backend checks do not establish physical Health delivery.

```sh
swift test --package-path Packages/SnoopHealth
xcodebuild -scheme Snoop -destination 'platform=iOS Simulator,name=Snoop UI Review' \
  -only-testing:SnoopUITests/HealthWeightTests test
```

The UI test uses only synthetic `UI-REVIEW` data at a development API. Override
`SNOOP_UI_SERVER_URL` in the runner; its default loopback port is 28474.

### Inspecting Trends

Tap a daily point or drag horizontally across the hero chart to inspect its recorded
value and exact date. Tap the selected headline to open that sleep's full details or
that day's hourly steps; Back preserves the selected reading. Latest clears selection,
and changing the metric or range starts fresh. Vertical swipes still scroll the page.
VoiceOver exposes previous/next readings and detail/reset actions. Sleep stage data
loads only when its detail page opens.

### Performance validation

See [performance and concurrency](docs/PERFORMANCE.md) for the internal architecture,
regression checks, synthetic UI fixture and physical-device validation boundaries.

### Manual ECG (experimental)

Profile → ECG offers guided, user-initiated WHOOP MG recordings with the existing
OS bond. The recorder acknowledges wrist selection, enables raw and filtered live
outputs, and starts generation once. Its 30-second phone capture window starts only
on a validated, nonempty filtered live record. Historical ECG, empty buffers and
exact duplicates do not advance it. A timeout or a gap prevents a success result.
Counted zero samples and unknown status codes remain intact; there is no inferred
contact-quality score, ECG heart-rate average, sample rate, voltage calibration or
rhythm diagnosis. CSV sharing uses sample indices and native counts.

Cancellation, backgrounding and disconnects stop the attempt. A durable cleanup
ledger is written before mutating requests; reconnect/relaunch performs cleanup for
the same strap without automatically starting another recording. Failed cleanup
blocks another start. Completed recordings are saved atomically in Application
Support/ECG and can be reopened offline. They are local to this iPhone; original
frames still use the normal durable upload queue and backend ECG decoder. There is
no new backend API or migration in this slice. `latest-attempt.json` contains only
command outcomes/counts for targeted troubleshooting, not waveforms or device IDs.

Run `swift test --package-path Packages/SnoopProtocol` and
`swift test --package-path Packages/SnoopECG`, plus `ECGRecorderTests` and
`ECGUITests` in the app's test scheme. Synthetic tests exercise malformed records,
refusal, no data, cancellation, lost connection, device isolation and restart cleanup.
A real clasp-contact recording remains the hardware acceptance check.

### Your progress

Trends → Your progress compares the last 28 complete local days with the preceding
28. Two cards show mean nightly sleep and daily steps with eight weekly bars.
Tap for wake-time consistency, walking minutes and resistance-training days.
Definitions and coverage thresholds are under About; this is descriptive progress,
not a health score. Missing weeks remain gaps, and comparisons appear only with
enough qualifying history in both periods. The server uses effective corrected
sleep and workouts. Opening Progress loads its summary; ordinary Trends chart
selection and range changes do not fetch it.

Backend contract: `/v1/devices/{device}/progress?tz=<IANA zone>` (see the backend's
`docs/PROGRESS.md`). `ProgressTests` covers formatting, missing data and stale-request
isolation; `ProgressUITests` covers navigation and large-text layouts using only
synthetic history from `tools/layout-test-server.py`.


### Weekly weight outlook

Goals → Start a cut explicitly enables a configurable weekly loss target.
The setup uses the existing measurement ruler and offers an optional Sunday 20:00
reminder. The server stores revisioned goal settings; the app caches them per
account/device, and never changes weight measurements or Health exports to meet a goal.
Goals uses the shared tab header and a target icon. Week medians and the selected
pace are separate from the raw Weight chart. Goals is the home for cut setup, progress
and editing. Today’s weight check-in opens only the Weight page; weight options contain
no goal controls. Edit goal supports pausing; restarting starts a fresh phase.
This navigation slice does not yet add maintenance, bulking, or an archive of past goals. Reminder day/time changes save with the goal without resetting pace.

Deploy backend migration 0014 and `/weight-goal` before installing. Weekly
notifications are calendar-based local reminders, scheduled by iOS without needing
to fetch measurements in the background. They contain neutral copy and open the
Goals tab with the latest available outlook after syncing. The goal timezone is fixed at setup. Pausing, disabling reminders or changing account removes the old
local request after reconciliation. Changes made on another device are picked up
on the next sync; they cannot revoke an offline device's notification immediately.

`WeeklyWeightTests` covers scheduling, permission, pause races, scope changes and
failed saves. `NotificationResponseTests` includes the weekly route on the main
thread. Run `python3 tools/weekly-weight-test-server.py` for `WeeklyWeightUITests`;
its loopback server uses synthetic data only. Backend algorithm and isolated
Postgres cases cover median robustness, sparse dates, goal changes and stall rules.

An optional finish date adds a calculated target weight and calendar-day progress.
Cut progress shows days remaining, elapsed time, and weight lost toward the goal.
Its chart uses the same axes, selection marker, and gestures as the Weight chart: swipe
to browse weeks, or hold and drag to inspect. The server currently supplies up to eight
recent weeks of the current pace phase. Historical medians show eligible adjacent-week
changes without reusing the latest verdict. Missing weeks break the line; incomplete
medians are isolated dots. Overall progress stays current while inspecting history.
The dashed planned path is omitted after a pace reset, so the new rate is not drawn
over old weeks. Goal weight and rate remain visible. No future measurements are drawn. Targets use the starting seven-day median and selected weekly
rate over calendar days. Baselines can be refined by late Health imports or corrections;
missing baselines remain unknown. Current progress uses the last seven calendar days,
without inventing missing readings. Finished cuts exclude all later weigh-ins.
The finish date does not restart pace comparisons; resuming a paused cut still does.
Dated reminders schedule up to eight upcoming one-shot weeks, refreshed on app sync,
so none can fire after the finish date even while offline. Open-ended cuts retain their
repeating reminder. Backend migration 0015 preserves existing open-ended goals.

The raw Weight chart includes the cut's calculated target as a dotted horizontal
line, labelled in the selected weight unit. Its axis includes the target, and the
line is clipped to the cut dates so browsing earlier periods does not imply a goal
existed then. Paused cuts and unknown targets have no line.
An optional daily step goal is saved with the cut. Today and the current-day Steps
page show the measured count against it; missing data remains unknown. It is hidden
for historical days, paused cuts, and after the finish date. Changing this goal does
not restart weight comparisons or change sensor measurements. Migration 0016 is
required for step-goal persistence; old clients preserve the setting when omitted.

Cut step reminders default to 22:00 and can be changed in cut setup or Profile →
Notifications. These are phone-local preferences. A one-shot reminder uses today's
last synced walking-step count, updates as Snoop syncs, and is cancelled when the
goal is reached, paused, removed, or the cut ends. No data means no reminder; a
confirmed zero-step day is eligible. The message explicitly says “at your last
sync” because iOS cannot guarantee a fresh fetch at the chosen time. Snoop must
run or wake and sync that day before the reminder time; future days are never
scheduled using today's count. Scheduled-at receipts prevent a second reminder
that day if the time changes after it was due; they do not prove delivery. There
is no late catch-up. Tapping opens Steps. Notification permission and Focus still
apply.


Daily step-goal completions are enabled by default, independently of the evening
reminder, under Profile → Notifications → Goal completions. A fresh current-day
walking count at or above an active cut's target sends “Steps goal complete” once
per account/device scope and local day. Tapping uses the existing Steps route.
Cached snapshots, historical days and inactive cuts cannot generate celebrations.
Lowering a target establishes a fresh baseline silently; edits never reset a day's
completion receipt. Denied or disabled alerts are not replayed after enabling.
Receipts survive relaunch; failed notification submissions can retry. Claiming a
receipt before submission favors avoiding duplicates if the app is terminated at
that boundary. Delivery remains subject to iOS permission, Focus and sync/wake
opportunities; this is not a guaranteed real-time step counter or remote push.
The existing progress bar turns green with a checkmark; a visible threshold
crossing gets one brief bounce and success haptic (no bounce with Reduce Motion).
