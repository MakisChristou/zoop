# Morning insights

`GET /v1/devices/{device}/days/{YYYY-MM-DD}/insights?tz=UTC` is authenticated and
read-only. It returns a date, time zone, insights version, source sleep identity and
revision, state, at most two factual observations, per-metric baseline and history,
weekly averages, and sleep timing variation. Invalid dates/zones return 400; missing
devices return 404. A known device without a main sleep returns `no_sleep`, not zero.

## Inputs and consistency

A repeatable-read snapshot selects one active effective main sleep per requested
local wake-up day (fixed main first, then longest, then stable id). Naps and removed
records are excluded. Queries are bounded to the target date and preceding 28 dates.
Each row retains its saved time zone for sleep-clock comparisons. Calendar grouping
uses the requested zone, matching the phone's selected day, including DST.

Pending sleep projections are `updating`; they do not enter the baseline. An
automatic night needs 270 recorded seconds, including 150 non-sleep seconds, in the
five minutes before onset; it also needs 1,500 recorded awake seconds in the first
30 minutes after its end. This guards both ends against truncated uploads. Otherwise
it is `awaiting_sync`. User-fixed bounds establish completion once metrics are ready
and the end is in the past. Missing evidence stays explicit even on an old date.

Quality is independent per metric:
- Sleep: at most 120 seconds missing within the selected period.
- HRV: at least 90% recording coverage, six usable five-minute windows, and usable
  windows covering at least half the expected bins.
- Resting HR: HR readings present in at least 90% of the period.
Nonfinite, zero or missing physiology is unavailable. The original measurement may
be shown with `limited` quality but cannot generate comparisons or chart points.

## Descriptive methods, version 2

Sources: Plews et al. 2014, doi:10.1123/ijspp.2013-0455 (repeated individual lnRMSSD);
Fischer et al. 2021, doi:10.1093/sleep/zsab103 (sleep timing variability).
The study populations and measurement protocols do not validate Snoop as a readiness
or medical tool. Window sizes, data gates and display bands below are explicit
product conventions, not clinical thresholds or a WHOOP formula.

Only dates before the target enter its baseline: 0–6 usable readings = learning,
7–13 = early average, 14+ = established average and descriptive one-standard-
deviation band. HRV is log-transformed before averaging/spread, then back-transformed.
Minimum half-widths are 15 minutes for sleep, 1 bpm for resting HR, and ln(1.05) for
HRV, preventing tiny changes around an invariant baseline from looking unusual.
A below/above/within-band label requires an established baseline. No recovery score
or physiological verdict is inferred. Early sleep comparisons are numerical
and visibly labelled early in the app.

The recent week includes the selected day plus six earlier dates. Five usable
readings are required for each metric independently. The preceding nonoverlapping
week needs five as well before its average is returned. Sleep timing is sample
standard deviation of local clock minutes, unwrapped around their circular mean;
23:50 and 00:10 are close. At least five complete nights in the same saved time zone
are required. This is timing variation, not SRI. Short nights are not rejected just
because they are short.

## Corrections and freshness

There is no separate persisted insight projection or processing cursor. Each request
reads the current effective sleep summaries and analysis state together. Editing,
removing, merging, resetting or undoing changes therefore affects the next read and
all later baselines whose 28-day window includes that date. Later measurement dates
never enter an earlier baseline, even if present in the database. Late uploads for
an older date can revise that date after the existing history worker catches up.

The app has one Today entry point, a detail page, an explanation sheet, date-specific
request protection, refresh on correction/analysis completion and retry on failure.
Learning and missing-data states are visible. This slice does not schedule alerts.
Sleep/workout algorithm versions and stored data do not change for insights v2.

## Validation

`just ci` covers the pure comparison rules; `SNOOP_TEST_DATABASE_URL=... just test-db`
includes `insights` API, coverage, correction/reset/undo, and historical-date tests
against isolated Postgres schemas. Fixtures are synthetic. UI tests use a separate
synthetic device and server; no screen mirroring is required for phone installation.

## Morning outlook presentation (v2)

The approved neutral Headline card uses `outlook` and each metric's `comparison`.
This is an explicit product presentation convention over the existing descriptive
bands, not a peer-reviewed readiness algorithm. The cited studies support the
measurements and comparisons, not the Good/Average/Low labels. Higher HRV or lower
resting HR can have several explanations; the labels do not diagnose recovery,
fitness, illness or capacity to train. No training recommendation is generated.

All three current metrics must have good coverage and at least 14 eligible prior
readings. Otherwise the outlook is `learning`, `limited`, or the recording's waiting
state, with no level. The progress count is the smallest independent baseline count.
Each usable metric can still show a numerical delta after seven prior readings;
its signal remains null and its text neutral until the baseline is established.

For display, sleep/HRV above their usual band and resting HR below its band are
`favourable`; the reverse is `unfavourable`; inside the band is `usual`.
`good` means at least one favourable and no unfavourable comparison; `low` means
at least one unfavourable and no favourable comparison. `average` means all three
are inside their usual bands. Opposing comparisons are `mixed`, never cancelled
into an average. Each delta retains its own colour, including in a mixed outlook.

The five neutral segments are ordinal: one unfavourable comparison = position 2,
two or three = 1; all usual = 3; one favourable = 4, two or three = 5. Mixed and
unavailable states omit the segments. This depicts agreement among comparisons,
not a measurement of physiological magnitude. Exact deltas below it supply the
magnitude: seconds for sleep (formatted as minutes/hours), percent change from the
geometric HRV average, and bpm for resting HR. No 0–100 score is invented.
