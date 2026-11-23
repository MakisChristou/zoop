//! Shared canonical phase outlook for API and agent readers.
use chrono::{DateTime, Utc};
use zoop_storage::{PostgresStore, WeightGoal};
/// Compute the existing weekly outlook without altering the goal.
/// # Errors
/// Database or calendar failure.
pub async fn goal_outlook(
    store: &PostgresStore,
    d: &str,
    g: &WeightGoal,
    now: DateTime<Utc>,
) -> crate::CoreResult<crate::WeightOutlook> {
    let today = store.weight_local_day(now, &g.timezone).await?;
    let started = store.weight_local_day(g.started_at, &g.timezone).await?;
    let pace = store
        .weight_local_day(g.pace_started_at, &g.timezone)
        .await?;
    let as_of = g.finish_date.map_or(today, |end| end.min(today));
    let cut_days = store
        .cut_weight_days(d, &g.timezone, started, as_of, now)
        .await?;
    let mut result = crate::phase_outlook(&cut_days, as_of, started, pace, g);
    result.progress = Some(crate::cut_progress(
        &cut_days,
        today,
        started,
        g.finish_date,
        if g.phase == "bulk" {
            -g.weekly_loss_kg
        } else {
            g.weekly_loss_kg
        },
    ));
    Ok(result)
}
