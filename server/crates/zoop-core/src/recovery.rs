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

/// Processes one durable observation without changing measured or sleep data.
/// # Errors
/// Storage or serialization failure; its claim remains retryable.
pub async fn observe_recovery(store: &PostgresStore) -> CoreResult<bool> {
    let Some(job) = store.claim_recovery(RECOVERY_VERSION).await? else {
        return Ok(false);
    };
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
    // Retain only the measurement inputs and gate provenance used by Recovery.
    // Sleep stages, timing charts and unrelated physiological metrics are omitted.
    let nights: Vec<_> = snapshot.nights.iter().map(|row| {
        let n = input_ref(row);
        let reading = |r: &zoop_analytics::insights::Reading| json!({"value":r.value,"quality":r.quality});
        json!({"day":n.day,"sleep_id":n.id,"revision":n.revision,"timezone":n.timezone,
            "measurement_version":row.metrics.pointer("/sleep/algo_version"),
            "day_count":row.day_count,"state":n.state,
            "sleep":reading(&n.sleep),"hrv":reading(&n.hrv),"resting_hr":reading(&n.resting_hr)})
    }).collect();
    let inputs = json!({"day":job.day,"timezone":job.tz,"sleep_version":ALGO_VERSION,
        "formula_version":RECOVERY_VERSION,"method":"zoop-recovery-v1","reference_seconds":28800,
        "pending":snapshot.pending,"nights":nights});
    let fingerprint = format!("{:x}", Sha256::digest(serde_json::to_vec(&inputs)?));
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
    if to < from || (to - from).num_days() > 365 {
        return Err(
            zoop_storage::StorageError::InvalidQuery("Invalid history window.".into()).into(),
        );
    }
    let Some(snapshot) = store
        .insight_snapshot(device, from - Duration::days(28), to, tz, ALGO_VERSION)
        .await?
    else {
        return Ok(Vec::new());
    };
    let mut result = Vec::new();
    for row in snapshot.nights.iter().filter(|n| n.day >= from) {
        let nights = snapshot
            .nights
            .iter()
            .filter(|n| n.day >= row.day - Duration::days(28) && n.day <= row.day)
            .cloned()
            .collect();
        let value = from_snapshot(
            row.day,
            tz,
            zoop_storage::InsightSnapshot {
                nights,
                pending: row.pending || row.day_pending,
            },
        )
        .recovery
        .score;
        result.push(json!({"day":row.day,"value":value}));
    }
    Ok(result)
}
