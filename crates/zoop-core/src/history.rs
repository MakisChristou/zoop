//! Restartable history processing using durable database jobs, not a moving time cursor.
use crate::{CoreResult, sleep_sessions::calculate_sleep_day, workouts::calculate_day};
use chrono::Utc;
use serde_json::json;
use std::time::{Duration, Instant};
use tokio_util::sync::CancellationToken;
use tracing::warn;
use zoop_analytics::{ALGO_VERSION, WORKOUT_ALGO_VERSION};
use zoop_storage::{AnalysisJob, AnalysisVersions, NewStrain, NewWorkout, PostgresStore};

/// A single worker can catch up all history; leases permit safe replacement or scaling.
#[derive(Debug, Clone)]
pub struct HistoryWorker {
    store: PostgresStore,
    enabled: bool,
    reconcile_interval: Duration,
}
impl HistoryWorker {
    /// Creates a worker; disabled workers report their pause while intake continues.
    pub const fn new(store: PostgresStore, enabled: bool, reconcile_interval: Duration) -> Self {
        Self {
            store,
            enabled,
            reconcile_interval,
        }
    }
    /// Independently versioned sleep and workout methods supported by this binary.
    pub const fn versions() -> AnalysisVersions {
        AnalysisVersions {
            sleep: ALGO_VERSION,
            workout: WORKOUT_ALGO_VERSION,
        }
    }
    /// Keeps unfinished work retryable through transient failures and cancellation.
    /// # Errors
    /// An unrecoverable worker failure (supervised by the service).
    pub async fn run(self, cancel: CancellationToken) -> CoreResult<()> {
        let mut next_seed = Instant::now();
        loop {
            if cancel.is_cancelled() {
                return Ok(());
            }
            let result = async {
                self.store
                    .worker_heartbeat("analysis", None, !self.enabled)
                    .await?;
                if !self.enabled {
                    return Ok(false);
                }
                if Instant::now() >= next_seed {
                    self.store.seed_history(Self::versions()).await?;
                    next_seed = Instant::now() + self.reconcile_interval;
                }
                self.pass().await
            }
            .await;
            let busy = match result {
                Ok(busy) => busy,
                Err(error) => {
                    warn!(%error,"history pass failed; retaining unfinished work");
                    let _ = self
                        .store
                        .worker_heartbeat("analysis", Some(&error.to_string()), !self.enabled)
                        .await;
                    false
                }
            };
            if !busy {
                tokio::select! {()=cancel.cancelled()=>return Ok(()),()=tokio::time::sleep(Duration::from_secs(5))=>{}}
            }
        }
    }
    /// Runs one claimed job. Useful for deterministic integration tests and operators.
    /// # Errors
    /// Storage or calculation failure; the job remains pending with backoff.
    pub async fn pass(&self) -> CoreResult<bool> {
        let Some(job) = self.store.claim_analysis(Self::versions()).await? else {
            return Ok(false);
        };
        if let Err(error) = self.calculate(&job).await {
            self.store.fail_analysis(&job, &error.to_string()).await?;
            return Err(error);
        }
        Ok(true)
    }
    async fn calculate(&self, job: &AnalysisJob) -> CoreResult<()> {
        if job.kind == "sleep" {
            let sessions =
                calculate_sleep_day(&self.store, &job.device_id, job.day, &job.tz).await?;
            let (from, to) = self.store.local_day_bounds(job.day, &job.tz).await?;
            self.store
                .publish_sleep_sessions(job, from, to, &sessions, WORKOUT_ALGO_VERSION)
                .await?;
        } else {
            let (from, to) = self.store.local_day_bounds(job.day, &job.tz).await?;
            let profile = self.store.profile_at(&job.device_id, to).await?;
            let result = calculate_day(
                &self.store,
                &job.device_id,
                profile.as_ref(),
                &job.tz,
                job.day,
            )
            .await?;
            let workouts: Vec<_> = result
                .as_ref()
                .map(|r| {
                    r.workouts
                        .iter()
                        .map(|w| NewWorkout {
                            device_id: &job.device_id,
                            algo_version: job.algo_version,
                            start_ts: w.start,
                            end_ts: w.end,
                            kind: w.kind.as_str(),
                            load: w.load as f32,
                            avg_hr: w.avg_hr as f32,
                            max_hr: i16::from(w.max_hr),
                            trimp: w.trimp as f32,
                            zones_min: w.zones.minutes().to_vec(),
                            kcal: w.kcal.map(|k| k as f32),
                            steps: i32::try_from(w.steps).unwrap_or(i32::MAX),
                        })
                        .collect()
                })
                .unwrap_or_default();
            let strain = result.as_ref().filter(|r| r.has_hr).map(|r| NewStrain {
                device_id: &job.device_id,
                day: job.day,
                algo_version: job.algo_version,
                load: r.load.load as f32,
                trimp: r.load.trimp as f32,
                zones_min: r.load.zones.minutes().to_vec(),
                kcal: r.kcal.map(|v| v as f32),
            });
            self.store
                .refresh_day_summary(&job.device_id, job.day, &job.tz)
                .await?;
            self.store.publish_day_sessions(job,zoop_storage::DayPublication {from,to,workouts:&workouts,strain:strain.as_ref(),inputs:json!({"proto_version":zoop_proto::PROTO_VERSION,
                "workout_version":WORKOUT_ALGO_VERSION,"tz":job.tz,"profile":profile,"physiology":result.as_ref().map(|r|&r.physiology),
                "params":result.as_ref().map(|r|&r.params),"calculated_at":Utc::now()}),sessions:Some(result.as_ref().map_or(&[],|r|r.sessions.as_slice()))}).await?;
        }
        Ok(())
    }
}
