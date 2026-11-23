//! Shared read contract for HTTP and MCP. Permission checks are not tool hints.
use crate::{
    error::{AgentError, AgentResult},
    state::AgentState,
};
use axum::{
    Extension, Json,
    extract::{Path, Query, State},
};
use chrono::{Duration, NaiveDate, Utc};
use serde::Deserialize;
use serde_json::{Map, Value, json};
use zoop_storage::AgentConnection;
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Range {
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}
pub(crate) const TOOLS: [(&str, &str, &str); 8] = [
    (
        "available_data",
        "Available data and connection permissions",
        "",
    ),
    (
        "daily_summary",
        "Daily measurements, only for permitted categories",
        "",
    ),
    (
        "sleep_history",
        "Effective sleep sessions, stages and timing",
        "sleep:read",
    ),
    (
        "recovery_history",
        "Recovery, nightly HRV and resting heart rate",
        "recovery:read",
    ),
    (
        "activity_history",
        "Workouts, filtered steps and daily load",
        "activity:read",
    ),
    (
        "weight_history",
        "Recorded weights and sources",
        "weight:read",
    ),
    (
        "goals",
        "Current and completed goal plans; progress also requires weight access",
        "goals:read",
    ),
    (
        "metric_definitions",
        "Units, missing data and metric definitions",
        "",
    ),
];
fn has(g: &AgentConnection, scope: &str) -> bool {
    g.scopes.iter().any(|s| s == scope)
}
pub(crate) async fn http(
    State(s): State<AgentState>,
    Extension(g): Extension<AgentConnection>,
    Path(tool): Path<String>,
    Query(q): Query<Range>,
) -> AgentResult<Json<Value>> {
    execute(&s, &g, &tool, q).await.map(Json)
}
pub(crate) async fn execute(
    s: &AgentState,
    g: &AgentConnection,
    tool: &str,
    q: Range,
) -> AgentResult<Value> {
    let (_, _, scope) = TOOLS
        .iter()
        .find(|(name, _, _)| *name == tool)
        .ok_or(AgentError::NotFound)?;
    if !scope.is_empty() && !has(g, scope) {
        return Err(AgentError::Forbidden);
    }
    let today = s.store.weight_local_day(Utc::now(), &g.timezone).await?;
    let earliest_allowed = g
        .history_days
        .map(|n| today - Duration::days(i64::from(n) - 1));
    let to = q.to.unwrap_or(today);
    let from = match q.from {
        Some(from) => from,
        None => to
            .checked_sub_signed(Duration::days(29))
            .ok_or(AgentError::Invalid("Invalid date range."))?
            .max(earliest_allowed.unwrap_or(NaiveDate::MIN)),
    };
    if to < from
        || to > today
        || (to - from).num_days() > 89
        || earliest_allowed.is_some_and(|min| from < min)
    {
        return Err(AgentError::Invalid(
            "Choose up to 90 days within this connection's history window.",
        ));
    }
    let mut data = Map::new();
    match tool {
        "available_data" => {
            let mut keys = Vec::new();
            for (scope, key) in [
                ("sleep:read", "sleep"),
                ("recovery:read", "recovery"),
                ("activity:read", "steps"),
                ("activity:read", "load"),
                ("activity:read", "workouts"),
                ("weight:read", "weight"),
            ] {
                if has(g, scope) {
                    keys.push(key.to_string());
                }
            }
            // A limited grant must not reveal whether older records exist.
            let earliest = match earliest_allowed {
                Some(day) => Some(day),
                None => {
                    s.store
                        .shared_earliest(&g.device_id, &g.timezone, &keys)
                        .await?
                }
            };
            data.insert("coverage".into(),json!({"history_window_start":earliest,"through":today,"scopes":g.scopes,"max_days_per_request":90,"rolling_history_days":g.history_days,"note":"Window bounds do not guarantee readings on every date."}));
        }
        "metric_definitions" => {
            data.insert("definitions".into(),json!({"sleep":"Effective main sleep belongs to the local wake date. Sessions also include naps. Sleep durations are seconds; stages are estimates.","recovery":"Zoop Recovery v1 is a 0–100 product index, not a clinical measure or WHOOP score. HRV is nightly RMSSD in milliseconds; resting HR is beats/minute.","activity":"Steps are backend walking/running-filtered counts. Load is Zoop's 0–21 display scale.","weight":"Measured kilograms; imported records retain their source. No averages are substituted for readings.","goals":"Pace and progress use the same backend outlook as iPhone and web. Full progress is withheld if its baseline predates permission.","missing":"Null means unavailable or pending, never zero. Recent data can change after sync or correction."}));
        }
        "sleep_history" => {
            data.insert(
                "sessions".into(),
                json!(
                    s.store
                        .agent_sessions(&g.device_id, &g.timezone, from, to, true)
                        .await?
                ),
            );
        }
        "recovery_history" => {
            data.insert("days".into(), recovery(s, g, from, to).await?);
        }
        "activity_history" => {
            data.insert(
                "workouts".into(),
                json!(
                    s.store
                        .agent_sessions(&g.device_id, &g.timezone, from, to, false)
                        .await?
                ),
            );
            points(
                s,
                g,
                &mut data,
                from,
                to,
                &[("steps", "steps"), ("load", "load")],
            )
            .await?;
        }
        "weight_history" => {
            data.insert(
                "readings".into(),
                json!(
                    s.store
                        .agent_weights(&g.device_id, &g.timezone, from, to)
                        .await?
                ),
            );
        }
        "goals" => {
            let current = s.store.agent_goal(&g.device_id).await?;
            if let Some(goal) = current {
                let start = s
                    .store
                    .weight_local_day(goal.started_at, &g.timezone)
                    .await?;
                // Never disclose an earlier baseline, even through a derived total.
                if start >= from && start <= to {
                    data.insert("current".into(),json!({"phase":goal.phase,"active":goal.active,"started_at":goal.started_at,"finish_date":goal.finish_date,"weekly_loss_kg":goal.weekly_loss_kg,"daily_steps_goal":goal.daily_steps_goal}));
                    // The goal's calendar can differ from consent. Avoid including
                    // weights from the preceding local day through its outlook.
                    if has(g, "weight:read") && to == today && goal.timezone == g.timezone {
                        data.insert(
                            "outlook".into(),
                            serde_json::to_value(
                                zoop_core::goal_outlook(&s.store, &g.device_id, &goal, Utc::now())
                                    .await?,
                            )
                            .map_err(|_| AgentError::Unavailable)?,
                        );
                    }
                } else {
                    data.insert("current".into(), Value::Null);
                    data.insert("current_status".into(), json!("outside_requested_window"));
                }
            }
            data.insert(
                "history".into(),
                json!(
                    s.store
                        .agent_goal_history(&g.device_id, &g.timezone, from, to)
                        .await?
                ),
            );
        }
        "daily_summary" => {
            if has(g, "sleep:read") {
                points(s, g, &mut data, from, to, &[("sleep_seconds", "sleep")]).await?;
            }
            if has(g, "recovery:read") {
                data.insert("recovery".into(), recovery(s, g, from, to).await?);
            }
            if has(g, "activity:read") {
                points(
                    s,
                    g,
                    &mut data,
                    from,
                    to,
                    &[("steps", "steps"), ("load", "load")],
                )
                .await?;
            }
            if has(g, "weight:read") {
                points(s, g, &mut data, from, to, &[("weight_kg", "weight")]).await?;
            }
        }
        _ => return Err(AgentError::NotFound),
    }
    let response = json!({"schema_version":1,"generated_at":Utc::now(),"timezone":g.timezone,"from":from,"to":to,"source":"zoop_backend","data":data});
    if response.to_string().len() > 512 * 1024 {
        return Err(AgentError::Invalid("Choose a shorter period."));
    }
    Ok(response)
}
async fn points(
    s: &AgentState,
    g: &AgentConnection,
    data: &mut Map<String, Value>,
    from: NaiveDate,
    to: NaiveDate,
    keys: &[(&str, &str)],
) -> AgentResult<()> {
    for (name, key) in keys {
        let version = if *key == "load" {
            zoop_analytics::WORKOUT_ALGO_VERSION
        } else {
            zoop_analytics::ALGO_VERSION
        };
        data.insert(
            (*name).into(),
            json!(
                s.store
                    .shared_points(&g.device_id, &g.timezone, from, to, key, version)
                    .await?
            ),
        );
    }
    Ok(())
}
async fn recovery(
    s: &AgentState,
    g: &AgentConnection,
    from: NaiveDate,
    to: NaiveDate,
) -> AgentResult<Value> {
    serde_json::to_value(
        zoop_core::daily_recovery_history(&s.store, &g.device_id, from, to, &g.timezone).await?,
    )
    .map_err(|_| AgentError::Unavailable)
}
