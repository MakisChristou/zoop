# Sleep and activity progress

`GET /v1/devices/{device}/progress?tz=Europe/London` is bearer-authenticated.
It compares the last 28 complete local dates with the preceding 28. The response
includes exact inclusive date bounds, timezone, observed counts, and eight weekly
values (oldest first). No schema or algorithm-version change is required.

This is a descriptive summary, not a health score, biological age, or prescription.
The window lengths and quality thresholds are product choices, not clinical cutoffs.

- Sleep: arithmetic mean of effective main-sleep duration, grouped by local wake
  date; user-confirmed records take precedence. Naps, pending analyses, incomplete
  boundaries and nights with over two minutes of unknown recording are excluded.
- Wake timing: circular standard deviation in clock minutes, using the recorded
  session timezone only when it matches the requested zone. Circular dispersion
  handles midnight; travel between zones is not treated as a timing improvement.
- Steps: mean walking/running-filtered counter increments on days with at least
  75% recording coverage. The denominator is the actual local-day length (DST).
- Walking: recorded walking/running seconds from the existing day summary, shown
  as mean minutes per complete recorded week. This is the strap activity label,
  not a new bout detector or guideline-intensity estimate.
- Strength: days with at least one active effective resistance session, assigned
  by local start date. Relabelled/removed sessions are respected and multiple
  sessions on a day count once. Pending workout analysis suppresses that day.

Daily comparisons require 21 qualifying dates in **each** 28-day window. Weekly
walking/strength totals require three fully recorded weeks in each period. There
is no extrapolation over missing days. A weekly sleep/steps bar needs four dates;
missing bars are null, recorded zeroes are zero. Headline means weight each date
equally rather than averaging uneven week means. Available means can appear
before comparisons qualify; the client must not invent a verdict or delta.

The iOS entry sits in Trends. Opening it loads the summary; switching existing
Trends ranges or metrics adds no requests. Each overview card has one number,
one eligible delta and eight bars. Definitions and coverage live in drill-downs
and About. Existing tabs and chart interactions are unchanged.

Validation: `just ci`; `ZOOP_TEST_DATABASE_URL=... just test-progress-db` uses
isolated development schemas. Contracts cover auth, invalid zones, unknown straps,
effective corrections, removed sessions, missing data and DST day length.
