---
id: measurements
slug: /measurements
title: Your measurements
description: What Zoop’s sleep, recovery, load and weight measurements mean.
---

# Your measurements

The server calculates Zoop’s metrics. The iPhone and web dashboard display the
same results, so corrections and new recordings can update both.

## Sleep

Zoop estimates sleep periods and stages from your recordings. Time asleep excludes
detected awake periods. The Sleep ring shows time asleep against your sleep goal;
nightly comparisons use your own history.

You can correct sleep times or merge periods the detector split. Corrections do
not remove the original recordings. Sleep stages are estimates, not a sleep study.

## Recovery

Recovery is a **0–100 Zoop index**, based on overnight HRV, resting heart rate and
recent sleep. It is independently calculated, not WHOOP’s score.

It needs at least 14 eligible prior nights within the previous 28 days, plus
sufficient recent recordings. Missing or unusual measurements can leave the score
unavailable; this does not mean zero Recovery.

Use it as context for your own patterns, not as a medical assessment or a validated
prediction of exercise readiness. The [method and its limitations](https://github.com/MakisChristou/zoop/blob/main/server/docs/recovery.md)
are documented with the source.

## Activity and load

Steps reflect Zoop’s filtered step count. Detected walk workouts must last more
than 30 minutes; shorter walks still contribute steps.

Load summarises heart-rate-based training effort on a **0–21 scale**. The scale
is Zoop’s presentation of training impulse, not WHOOP’s Strain algorithm.
You can correct a detected workout’s type or timing without altering raw recordings.

## Weight and goals

Log weight on your iPhone or import it from Apple Health. Cut, bulk and maintenance
phases keep their own progress and weekly outlook. Daily weight can fluctuate;
weekly summaries help you follow the trend.

Apple Health access is optional and permission-based. Zoop does not need it to
collect recordings from your band.

## Why a value might be missing

The band may still be syncing, analysis may be pending, or the recording may not
contain enough usable data. Some measurements also need a personal baseline.
Zoop leaves missing values empty instead of inventing a reading.

See [troubleshooting](HELP.md) if new recordings are not reaching the server.
