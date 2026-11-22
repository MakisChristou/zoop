//! Recovery observations use exactly the same read-only calculation as the API.
use crate::{
    CoreResult,
    insights::{from_snapshot, input_ref},
};
use chrono::Duration;
use serde_json::json;
use sha2::{Digest, Sha256};
use zoop_analytics::{ALGO_VERSION, recovery::RECOVERY_VERSION};
use zoop_storage::PostgresStore;

/// A private daily chart reading from the same snapshot as its supporting metrics.
#[derive(Debug, serde::Serialize)]
pub struct RecoveryDay {
    pub day: chrono::NaiveDate,
    pub recovery: zoop_analytics::recovery::Recovery,
    pub hrv_ms: Option<f64>,
    pub resting_hr: Option<f64>,
}

/// Processes one durable observation without changing measured or sleep data.
/// # Errors
/// Storage or serialization failure; its claim remains retryable.
pub async fn observe_recovery(store: &PostgresStore) -> CoreResult<bool> {
    let Some(job) = store.claim_recovery(RECOVERY_VERSION).await? else {
        return Ok(false);
    };
    store
        .refresh_sleep_evidence(
            &job.device_id,
            job.day - Duration::days(28),
            job.day,
            &job.tz,
            ALGO_VERSION,
        )
        .await?;
    let Some(snapshot) = store
        .insight_snapshot(
            &job.device_id,
            job.day - Duration::days(28),
            job.day,
            &job.tz,
            ALGO_VERSION,
        )
        .await?
    else {
        return Ok(false);
    };
    let (fingerprint, inputs) = recovery_inputs(job.day, &job.tz, &snapshot)?;
    let result = serde_json::to_value(from_snapshot(job.day, &job.tz, snapshot).recovery)?;
    store
        .record_recovery(&job, &fingerprint, &inputs, &result)
        .await?;
    Ok(true)
}

/// Bounded public history using the identical calculation and quality gates as insights.
/// One consistent snapshot supplies all days and their 28-day baselines.
/// # Errors
/// Invalid range or database failure.
pub async fn recovery_history(
    store: &PostgresStore,
    device: &str,
    from: chrono::NaiveDate,
    to: chrono::NaiveDate,
    tz: &str,
) -> CoreResult<Vec<serde_json::Value>> {
    // Public sharing deliberately projects only the selected Recovery metric.
    Ok(daily_recovery_history(store, device, from, to, tz)
        .await?
        .unwrap_or_default()
        .into_iter()
        .map(|row| json!({"day": row.day, "value": row.recovery.score}))
        .collect())
}

/// Private bounded history, including the nightly measurements shown by insights.
/// Returns `None` for an unknown device. Dates with no main sleep are omitted.
/// # Errors
/// Invalid range or database failure.
pub async fn daily_recovery_history(
    store: &PostgresStore,
    device: &str,
    from: chrono::NaiveDate,
    to: chrono::NaiveDate,
    tz: &str,
) -> CoreResult<Option<Vec<RecoveryDay>>> {
    if to < from || (to - from).num_days() > 365 {
        return Err(
            zoop_storage::StorageError::InvalidQuery("Invalid history window.".into()).into(),
        );
    }
    let Some(snapshot) = store
        .insight_snapshot(device, from - Duration::days(28), to, tz, ALGO_VERSION)
        .await?
    else {
        return Ok(None);
    };
    let mut days = Vec::new();
    for row in snapshot.nights.iter().filter(|n| n.day >= from) {
        let nights = snapshot
            .nights
            .iter()
            .filter(|n| n.day >= row.day - Duration::days(28) && n.day <= row.day)
            .cloned()
            .collect();
        let daily = zoop_storage::InsightSnapshot {
            nights,
            pending: row.pending || row.day_pending,
        };
        let (fingerprint, _) = recovery_inputs(row.day, tz, &daily)?;
        days.push((row.day, daily, fingerprint));
    }
    let fingerprints = days
        .iter()
        .map(|(_, _, fingerprint)| fingerprint.clone())
        .collect::<Vec<_>>();
    let stored = store
        .recovery_results(device, tz, RECOVERY_VERSION, &fingerprints)
        .await?;
    let mut result = Vec::new();
    for (day, daily, fingerprint) in days {
        let cached = stored
            .get(&fingerprint)
            .cloned()
            .map(serde_json::from_value)
            .transpose()?;
        let brief = crate::insights::from_snapshot_with_recovery(day, tz, daily, cached);
        let metric = |key| {
            brief
                .metrics
                .iter()
                .find(|m| m.key == key)
                .and_then(|m| m.value)
        };
        result.push(RecoveryDay {
            day,
            hrv_ms: metric("hrv"),
            resting_hr: metric("resting_hr"),
            recovery: brief.recovery,
        });
    }
    Ok(Some(result))
}

/// Exact scoring inputs identify reusable observations, including transient gates.
pub(crate) fn recovery_inputs(
    day: chrono::NaiveDate,
    tz: &str,
    snapshot: &zoop_storage::InsightSnapshot,
) -> CoreResult<(String, serde_json::Value)> {
    // Retain only the measurement inputs and gate provenance used by Recovery.
    // Sleep stages, timing charts and unrelated physiological metrics are omitted.
    let nights: Vec<_> = snapshot.nights.iter().map(|row| {
        let n = input_ref(row);
        let reading = |r: &zoop_analytics::insights::Reading| json!({"value":r.value,"quality":r.quality});
        json!({"day":n.day,"sleep_id":n.id,"revision":n.revision,"timezone":n.timezone,
            "measurement_version":row.metrics.pointer("/sleep/algo_version"),
            "day_count":row.day_count,"day_pending":row.day_pending,"state":n.state,
            "sleep":reading(&n.sleep),"hrv":reading(&n.hrv),"resting_hr":reading(&n.resting_hr)})
    }).collect();
    let inputs = json!({"day":day,"timezone":tz,"sleep_version":ALGO_VERSION,
        "formula_version":RECOVERY_VERSION,"method":"zoop-recovery-v1","reference_seconds":28800,
        "evidence_version":1,"pending":snapshot.pending,"nights":nights});
    Ok((
        format!("{:x}", Sha256::digest(serde_json::to_vec(&inputs)?)),
        inputs,
    ))
}
