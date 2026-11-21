# Recovery

Zoop calculates one daily Recovery index on the server. iPhone and web display
that same result. It is a Zoop-owned index, not WHOOP's algorithm, a clinical
measurement, or a validated probability of readiness for exercise.

## Version 1

The frozen research candidate v0.3 is now `zoop-recovery-v1`. Its version is
independent of sleep detection and workout analysis. Changing a sleep goal in
the interface does not change historical Recovery scores.

- Use the previous 28 **local calendar dates**, excluding the assessed night.
- Require 14 prior main sleeps with paired eligible HRV, resting heart rate,
  and time asleep, and five eligible nights in the latest seven dates including
  the assessed night. No interpolation, naps, future nights, or zero filling.
- Scope to the requested device, its current sleep measurement version, and the
  assessed night's saved timezone. Duplicate main sleeps in the same context
  are ambiguous even if one has poor quality or pending metrics.
- Keep the existing recording-completeness, pending-analysis and per-metric
  coverage gates. An edit awaiting recalculation has no score.

Let `h` be the assessed night's ln(HRV) standardized against the prior paired
nights, using sample standard deviation with a floor of ln(1.05). Let `r` be
similarly standardized resting heart rate, with a 1 bpm SD floor.

```
H = clamp(75 + 15h, 0, 100)
R = clamp(75 - 15r, 0, 100)
S = 100 × min(last sleep / 28,800 seconds, 1)²
W = 100 × mean(min(each recent sleep / 28,800 seconds, 1))²
score = floor(min(H, R, S, W) + 0.5 + 1e-9)
```

The 1e-9-point tolerance makes exact half-up boundaries stable across floating-point
logarithm and standard-deviation implementations.

Unusually high HRV (`h > 2`) or low resting HR (`r < -2`) yields
`unusual_signals` with no score, rather than an automatic favorable result.
Opposing HRV/RHR directions beyond one SD set `conflict`; the lowest component
still limits the score. There is no oversleep bonus and a long latest night does
not erase the recent-sleep component. The eight-hour reference, 75 centre,
15-point slope, minimum-component rule and thresholds are product conventions.
The display bands `<34 low`, `<67 moderate`, and otherwise `high` are also
conventions; they are not clinically calibrated thresholds.

Plews et al. (2014), [doi:10.1123/ijspp.2013-0455](https://doi.org/10.1123/ijspp.2013-0455),
supports repeated personal lnRMSSD measurement. Banks et al. (2010),
[PMID:20815182](https://pubmed.ncbi.nlm.nih.gov/20815182/), supports considering
accumulated sleep restriction. Neither paper establishes or validates this
composite formula. The existing wrist-derived HRV and sleep limitations remain.

## API and provenance

`GET /v1/devices/{device}/days/{day}/insights` adds `recovery` without changing
existing metrics or Outlook. Authorization remains the existing device-owner
check. The object includes `version`, `method`, `state`, nullable `score`,
`baseline_count`, `recent_count`, `reference_seconds`, nullable `components`,
`limiting`, `conflict`, and nullable `band`. Only `ready` has a numeric score.
A missing or unsupported measurement is not zero Recovery.

GET calculates from a single repeatable-read snapshot and never writes. The
existing analysis worker records the same calculation in append-only
`recovery_observations`, with only scoring values, eligibility states, source IDs/revisions, measurement
version, saved timezone and duplicate counts (not stage arrays), a SHA-256 input fingerprint,
formula version, and observation time. Observation time is calculation time,
not proof that a user viewed a score. Corrections and late data append a revised
observation; earlier evidence remains intact.

Migration 0020 adds observations and a small coalescing queue. A sleep publication
atomically enqueues its date and existing main-sleep dates up to 28 days later,
never future calendar dates. Initial reconciliation seeds existing main-sleep
dates once per device, timezone, and formula version; it does not redetect sleep.
Each worker loop handles at most one observation. Failed claims retry after
30 seconds; generation fencing retains new work if inputs change concurrently.

## Validation

Pure tests cover all component anchors, short and repeated restricted sleep,
missing and unusual signals, duplicate revisions, timezone/calendar boundaries,
paired-history requirements, rounding and output bounds. Forty deterministic
vectors compare Rust scores and every component with frozen Python v0.3 results.
Database tests use isolated development schemas to exercise the wire contract,
measurement-version gates, read-only GETs, device isolation, correction pending
states, append-only revisions, retries and bounded bootstrap.

This is implementation validation, not clinical validation or evidence of
population accuracy. A larger longitudinal validation remains useful before
making stronger health or performance claims.

## Daily chart

`GET /v1/devices/{device}/recovery?from=YYYY-MM-DD&to=YYYY-MM-DD&tz=Area/City`
returns an inclusive, ownership-checked history window (at most 366 days). Each
row contains `day`, the same `recovery` object as daily insights, `hrv_ms`, and
`resting_hr` from that night's insights. One read-only snapshot supplies the
window and its preceding 28-day baselines. Dates without main sleep are omitted;
clients render gaps, not zeros. Pending or ineligible nights retain their state
and null score. This does not change the formula or persist new observations.
Public sharing continues to expose only its selected score projection, never the
additional private tooltip measurements.
