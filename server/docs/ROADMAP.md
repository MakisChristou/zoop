# Roadmap

The primary goal is **sleep tracking that matches the official WHOOP app** for the
WHOOP 5.0 and MG: the same nights, the same onset and wake times, stage totals that
agree, and the same sleep performance figures as closely as public methods allow.
Everything else is secondary and comes after.

## Milestones

1. **Backend skeleton** — done. Ingest, raw storage, decode worker, R18 / ECG / event
   decoding, config, CLI, CI.
2. **First real data** — iOS app connects to a strap, streams live HR, uploads frames.
   Replace synthetic protocol fixtures with captures from our own hardware.
3. **History offload** — GET_DATA_RANGE, SEND_HISTORICAL_DATA, token-echo ACK loop,
   background Bluetooth. Full nights land in `samples`.
4. **Sleep v1** — see below. Nightly sleep windows, efficiency, resting HR, HRV,
   respiratory rate.
5. **Sleep v2** — four-class staging (wake / light / deep / REM) — first version done; sleep need and
   sleep debt, comparison tooling against official-app exports.
6. **Workouts v1** — done. Automatic walks and resistance training, day load, body
   profile, user labels. See below.
7. **Recovery**, journal, dashboard.

## Sleep plan

Inputs available at 1 Hz from R18: heart rate, R-R intervals, dynamic acceleration,
gravity vector, skin temperature, the strap's band state (wake / still / sleep / up),
and SpO₂ windows. R21 IMU records add six-axis motion when needed.

**Sleep window (v5).** The band state is WHOOP's own on-device rest flag and is the
best available anchor for sleep/wake boundaries. Per-second sleep flags are
majority-smoothed over a 5-minute window, gaps up to 45 minutes are merged, and
windows under 10 minutes are discarded. This cutoff is a product choice, not a
clinical definition. With at least 600 heart-rate readings in a window, mean HR
must not exceed 1.05 times the awake median. Naps pass the same checks as overnight
sleep; the longest automatic window is main sleep unless a user-confirmed main
sleep takes precedence. Short naps can still be missed if the strap marks sleep
late. Raw samples and manual corrections are preserved during versioned reanalysis.

**Per-night metrics (v1).** Time in bed, total sleep time, latency, wake after sleep
onset, efficiency; resting HR as the lowest sustained 5-minute mean; HRV as the mean of
5-minute RMSSD windows over clean R-R; respiratory rate from the R-R tachogram spectrum
(respiratory sinus arrhythmia, 0.1–0.5 Hz); nightly skin temperature baseline.

**Staging (v2).** Thirty-second epochs with features: mean HR, HR difference-of-Gaussians
variability, RMSSD/SDNN, respiratory rate and its variability, motion fraction.
Classification against night-relative percentiles: wake = motion plus cardiac
activation; deep = still, low HR, high RMSSD, regular breathing; REM = still, cardiac
activation, irregular breathing; light otherwise. Five-epoch median smoothing, no REM
in the first 15 minutes, deep weighted to the first third of the night. Methods:
Cole–Kripke / Webster actigraphy, van Hees z-angle immobility, Walch et al. 2019
HR-based staging, Task Force 1996 HRV. Each module cites its source.

**Validation.** The strap keeps a single history stream: whichever app drains it owns
that data, and the other app sees a gap. The official app therefore cannot score a
night that zoop has already pulled, and vice versa. Validation alternates nights:
on reference nights the official app syncs and its sleep export is kept; on zoop
nights we compute ours. Compare the two populations (onset and wake relative to the
strap's own sleep flag, stage totals, efficiency) and keep a scorecard per algorithm
version. The target is agreement within a few minutes on boundaries and within the
published inter-device error on stage totals.

## Workout plan

Inputs: the strap's own per-second walk/run label, its step counter, heart rate, band
state and the analysed sleep windows. No raw inertial data (see `MOTION.md`).

**Sessions (v1).** A minute exerts when its mean heart rate reaches 40 % of heart-rate
reserve (Karvonen 1957; the ACSM moderate threshold, Garber et al. 2011) or the strap
labels most of it as walking. Exerting minutes chain across rests of up to five minutes,
which keeps the recovery between sets inside one resistance session. Mostly ambulatory
sessions of ten minutes or more are walks; sessions of twenty minutes or more with
hardly any walking are resistance training; the rest is unlabelled activity for the
user to name. Resting heart rate comes from the latest analysed night; maximal heart
rate from Tanaka et al. 2001 on the profile's age (40 assumed when unknown), raised to
the highest one-minute mean the strap has seen in 90 days.

**Load.** Edwards 1993 summated-zone training impulse over five zones of maximal heart
rate, per session and over the awake day, shown on a 0–21 saturating display scale that
is documented as presentation, not measurement. Calories per session from Keytel et al.
2005 on heart rate, weight, age and sex; the equations are fitted on exercise, so they
are never summed over rest.

**Walking bouts.** Troiano 2008 bout rules on the strap's walk label with two-minute
interruptions tolerated; cadence read against Tudor-Locke & Rowe 2012.

**Corrections.** The user may relabel a session's kind. Labels are stored unversioned
by time span and matched to sessions by overlap, so a recompute at a new
`algo_version` keeps them. The body profile and home time zone are likewise inputs,
not derived data.

## Non-goals for now

Blood-pressure insights, Healthspan-style ages, and anything requiring WHOOP's
proprietary models or lab data.

## Workout corrections

Stable, revisioned workout corrections support time/type edits, continuous merges,
splits, removal/restore, and adding missed intervals with sensor data. Correction
publication uses the durable history queue and input fence. See
[WORKOUT_CORRECTIONS.md](WORKOUT_CORRECTIONS.md) for contracts and validation.
Real walk and gym accuracy remains a device-validation task.

## Morning insights

Personal comparisons, baseline learning, a seven-day summary and sleep-timing
variation are implemented as descriptive observations. See
[MORNING_INSIGHTS.md](MORNING_INSIGHTS.md). Recovery scoring remains future work.
