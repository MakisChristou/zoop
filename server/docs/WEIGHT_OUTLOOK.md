# Weight outlook, version 2

Descriptive feedback for cut, bulk and indefinite maintenance. The API owns the
calculation; clients display it. No calories, tissue composition or physiological
cause is inferred. A sustained trend can still reflect water or other factors.

## Evidence and limits

Weekly alignment follows Orsama et al., *Weight Rhythms*, Obesity Facts (2014),
[doi:10.1159/000356147](https://doi.org/10.1159/000356147).
The median's resistance to isolated outliers is described in
[NIST Dataplot](https://itl.nist.gov/div898/software/dataplot/refman1/auxillar/mediancl.htm).
[RP's guidance](https://rpstrength.com/blogs/articles/why-youre-not-losing-weight)
supports comparing weekly aggregates rather than individual weigh-ins.

Our eligibility, tolerances and persistence rules below are explicit product
heuristics, not an RP formula or clinically validated diagnostic thresholds.

## Inputs

One canonical weight per local day: Health source first, then latest timestamp/id.
Removed, future and invalid readings are excluded. Never interpolate missing days.
Use the saved phase timezone and Monday–Sunday weeks. A qualifying week has at
least four days, with first/last readings at least four days apart. Partial opening
weeks and weeks before a pace revision remain ungraded. Missing weeks break the
comparison; calendar time is never compressed. Sunday is provisional; late data
can update a report without sending another notification.

## Cut and bulk

The stored `weekly_loss_kg` remains a positive magnitude for wire compatibility.
`phase` determines direction: negative cut rate, positive bulk rate, zero maintenance.
For signed target `r`, tolerance is `min(max(0.10, 0.25*abs(r)), 0.50*abs(r))` kg/week.
With three consecutive qualifying medians A, B, C, pace is `(C-A)/2` kg/week.
Within the inclusive tolerance: On pace. Otherwise: Watching until either both
weekly changes B-A and C-B deviate on the same side, or the previous three-week
pace also deviated on that side. The latter needs a fourth qualifying week and
catches alternating flat/on-target weeks. Confirmed deviations are Below pace or
Above pace according to phase direction. Returning inside the band clears them.

Possible stall additionally requires both weekly changes to be within 0.1% of
starting weight of zero and confirmed below-pace progress. Sparse data never
counts as a stall or success.

Total progress separately uses first/latest phase readings. Target weight equals
first reading plus signed rate times planned duration. Closed targets are frozen;
corrections can update observations without rewriting the intended goal.

## Maintenance

Maintenance is a durable phase, automatically created when a dated goal finishes
or is ended. It has no required finish date. Its reference is the median of the
first qualifying full week, learned once after that week ends. Users can explicitly
change it. It never automatically follows later drift. Default range is ±1%; users
can choose 0.5–5%. The initial two qualifying weeks are a settling period.

After three qualifying weeks, evaluate in this order:

1. Latest two medians outside the same range boundary: Above/Below range.
2. Confirmed pace above/below 0.1% of fixed reference per week, using the same
   persistence gates: Drifting up/down, even while inside the range.
3. One outside-range median or unconfirmed pace deviation: Watching.
4. Otherwise: Stable. Missing reference/history: Building trend.

Reference/range/rate/timezone changes reset pace assessment; steps and reminder
edits do not. Each phase owns its steps target. Automatic maintenance restores the
most recent maintenance steps preference or leaves the target unset; it never
inherits a cut's target by accident.

## Lifecycle and notifications

Device-scoped revision checks and advisory locks protect changes. Archiving and
starting a replacement phase are atomic; retries do not duplicate periods. Existing
cut identities survive migration. No prior maintenance history is fabricated.

Weekly notifications are generic, account-scoped local calendar requests on iOS,
so they continue across automatic transitions without claiming a stale result.
Opening fetches the current phase. Web changes reconcile on the phone's next sync.
Notification permission, Focus and OS delivery behavior still apply.

Tests cover water-like rebounds, persistent/alternating deviations, sign symmetry,
missing data, fixed references, source precedence, boundaries, transitions and
concurrent commands. These test deterministic behavior, not clinical validity.
