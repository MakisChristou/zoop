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
5. **Sleep v2** — four-class staging (wake / light / deep / REM), sleep need and
   sleep debt, comparison tooling against official-app exports.
6. **Recovery and strain**, workouts, journal, dashboard.

## Sleep plan

Inputs available at 1 Hz from R18: heart rate, R-R intervals, dynamic acceleration,
gravity vector, skin temperature, the strap's band state (wake / still / sleep / up),
and SpO₂ windows. R21 IMU records add six-axis motion when needed.

**Sleep window (v1).** The band state is WHOOP's own on-device rest flag and is the
best available anchor for sleep/wake boundaries. Per-second sleep flags are
majority-smoothed over a 5-minute window, gaps up to 10 minutes are merged, and
periods under 20 minutes are discarded. Each window is confirmed cardiac-wise: mean HR
inside must sit below the day's awake baseline. Naps are windows outside the main
night that pass the same tests with stricter minimums.

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
night that snoop has already pulled, and vice versa. Validation alternates nights:
on reference nights the official app syncs and its sleep export is kept; on snoop
nights we compute ours. Compare the two populations (onset and wake relative to the
strap's own sleep flag, stage totals, efficiency) and keep a scorecard per algorithm
version. The target is agreement within a few minutes on boundaries and within the
published inter-device error on stage totals.

## Non-goals for now

Blood-pressure insights, Healthspan-style ages, and anything requiring WHOOP's
proprietary models or lab data.
