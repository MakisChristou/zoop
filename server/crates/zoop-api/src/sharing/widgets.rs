//! Allowlisted presentation payloads. Never serialize private session or goal records.
use crate::{AppState, error::ApiError};
use chrono::{Duration, NaiveDate, Utc};
use serde_json::{Value, json};

async fn night(
    s: &AppState,
    device: &str,
    tz: &str,
    day: NaiveDate,
) -> Result<Option<zoop_storage::InsightNight>, ApiError> {
    Ok(s.store
        .insight_snapshot(device, day, day, tz, zoop_analytics::ALGO_VERSION)
        .await?
        .and_then(|snapshot| {
            snapshot
                .nights
                .into_iter()
                .find(|n| n.day == day && n.end_ts <= Utc::now())
        }))
}

pub(super) async fn sleep_reading(
    s: &AppState,
    device: &str,
    tz: &str,
    day: NaiveDate,
) -> Result<(Value, &'static str), ApiError> {
    let Some(n) = night(s, device, tz, day).await? else {
        return Ok((Value::Null, "missing"));
    };
    if n.pending || n.day_pending {
        return Ok((Value::Null, "updating"));
    }
    Ok((
        n.metrics
            .pointer("/sleep/window/asleep_s")
            .cloned()
            .unwrap_or(Value::Null),
        "ready",
    ))
}

pub(super) async fn project(
    s: &AppState,
    device: &str,
    tz: &str,
    from: NaiveDate,
    to: NaiveDate,
    key: &str,
) -> Result<Option<Value>, ApiError> {
    if ["sleep_timeline", "sleep_stages", "nightly_metrics"].contains(&key) {
        let Some(n) = night(s, device, tz, to).await? else {
            return Ok(Some(
                json!({"key":key,"day":to,"state":"missing","night":null}),
            ));
        };
        if n.pending || n.day_pending {
            return Ok(Some(
                json!({"key":key,"day":to,"state":"updating","night":null}),
            ));
        }
        let m = &n.metrics;
        let value = |path| m.pointer(path).cloned().unwrap_or(Value::Null);
        if key == "nightly_metrics" {
            return Ok(Some(json!({"key":key,"day":to,"state":"ready","metrics":{
                "resting_hr":value("/sleep/physiology/resting_hr"),"hrv_rmssd_ms":value("/sleep/physiology/hrv_rmssd_ms"),
                "respiratory_rate":value("/sleep/physiology/respiratory_rate"),"efficiency":value("/sleep/window/efficiency"),"partial":value("/sleep/partial")
            }})));
        }
        let mut sleep = json!({"window":{"asleep_s":value("/sleep/window/asleep_s"),"onset":value("/sleep/window/onset"),"offset":value("/sleep/window/offset")},"partial":value("/sleep/partial")});
        if key == "sleep_stages" {
            sleep["stages"] = json!({"deep_s":value("/sleep/stages/deep_s"),"rem_s":value("/sleep/stages/rem_s"),"light_s":value("/sleep/stages/light_s"),"wake_s":value("/sleep/stages/wake_s")});
        } else {
            sleep["segments"] = json!(
                m.pointer("/sleep/segments")
                    .and_then(Value::as_array)
                    .map(|rows| rows
                        .iter()
                        .map(|r| json!({"stage":r["stage"],"start":r["start"],"end":r["end"]}))
                        .collect::<Vec<_>>())
                    .unwrap_or_default()
            );
        }
        return Ok(Some(
            json!({"key":key,"day":to,"state":"ready","night":{"start_ts":n.start_ts,"end_ts":n.end_ts,"timezone":n.timezone,"sleep":sleep}}),
        ));
    }
    if key == "morning_outlook" {
        let insight = zoop_core::morning_insights(&s.store, device, to, tz).await?;
        let brief = insight.map(|b| json!({"state":b.state,"outlook":{"state":b.outlook.state},"metrics":b.metrics.iter().filter(|m| ["sleep", "hrv", "resting_hr"].contains(&m.key)).map(|m| json!({"key":m.key,"value":m.value,"comparison":m.comparison})).collect::<Vec<_>>()}));
        return Ok(Some(json!({"key":key,"day":to,"insight":brief})));
    }
    if ["goal_progress", "goal_weight"].contains(&key) {
        let Some(goal) = s.store.weight_goal(device).await?.filter(|g| g.active) else {
            return Ok(Some(json!({"key":key,"goal":null})));
        };
        // End-of-day in the goal timezone, clamped to now; never include future observations.
        let end = s
            .store
            .local_day_bounds(to + Duration::days(1), &goal.timezone)
            .await?
            .0;
        let now = (end - Duration::microseconds(1)).min(Utc::now());
        let start = s
            .store
            .weight_local_day(goal.started_at, &goal.timezone)
            .await?;
        if start > to {
            return Ok(Some(json!({"key":key,"goal":null})));
        }
        let mut summary = crate::weight_goal::summary(s, device, &goal, now).await?;
        summary.weeks.retain(|w| w.start >= from && w.end <= to);
        if let Some(p) = summary.progress.as_mut() {
            p.weigh_ins.retain(|w| w.day >= from && w.day <= to);
            if key == "goal_progress" {
                p.weigh_ins.clear();
            }
        }
        let summary = json!({"state":summary.state,"week_number":summary.week_number,"median_kg":summary.median_kg,"change_kg":summary.change_kg,"maintenance_lower_kg":summary.maintenance_lower_kg,"maintenance_upper_kg":summary.maintenance_upper_kg,"weeks":summary.weeks,"progress":summary.progress});
        return Ok(Some(
            json!({"key":key,"day":to,"as_of":now,"goal":{"phase":goal.phase,"active":goal.active,"started_at":goal.started_at,"finish_date":goal.finish_date,"timezone":goal.timezone,"daily_steps_goal":goal.daily_steps_goal},"summary":summary}),
        ));
    }
    Ok(None)
}
