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

## Descriptive methods, version 1

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
or good/bad physiological verdict is inferred. Early sleep comparisons are numerical
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
Sleep/workout algorithm versions and stored data do not change for insights v1.

## Validation

`just ci` covers the pure comparison rules; `SNOOP_TEST_DATABASE_URL=... just test-db`
includes `insights` API, coverage, correction/reset/undo, and historical-date tests
against isolated Postgres schemas. Fixtures are synthetic. UI tests use a separate
synthetic device and server; no screen mirroring is required for phone installation.
