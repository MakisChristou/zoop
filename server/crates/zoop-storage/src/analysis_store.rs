//! Durable, coalesced analysis work. Leases fence crashed workers; generations fence
//! input changes. A result and its completion marker are published in one transaction.
use crate::{
    NewSleep, NewStrain, NewWorkout, PostgresStore, StorageError, StorageResult, StoreOperation,
};
use chrono::{DateTime, NaiveDate, Utc};
use serde_json::Value;
use sqlx::{FromRow, PgConnection};

/// Independent method versions, supplied by the analytics layer.
#[derive(Debug, Clone, Copy)]
pub struct AnalysisVersions {
    pub sleep: i32,
    pub workout: i32,
}
/// One leased revision of an analysis period.
#[derive(Debug, Clone, FromRow)]
pub struct AnalysisJob {
    pub device_id: String,
    pub kind: String,
    pub day: NaiveDate,
    pub tz: String,
    pub algo_version: i32,
    pub generation: i64,
    pub claim_id: i64,
    pub backfill: bool,
}
/// Per-device progress. A recent sample alone does not imply history is complete.
#[derive(Debug, serde::Serialize, FromRow)]
pub struct ProcessingStatus {
    pub pending_decode: i64,
    pub decode_failures: i64,
    pub pending_analysis: i64,
    pub failed_analysis: i64,
    pub oldest_pending_day: Option<NaiveDate>,
    pub last_analyzed_at: Option<DateTime<Utc>>,
    pub workers_healthy: bool,
    pub paused: bool,
}
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Analysis, e)
}

impl PostgresStore {
    /// Schedules an explicit recalculation without bypassing the durable writer.
    /// # Errors
    /// Database failure.
    pub async fn request_analysis(
        &self,
        device: &str,
        kind: &str,
        day: NaiveDate,
        tz: &str,
        version: i32,
        backfill: bool,
    ) -> StorageResult<()> {
        sqlx::query("INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,backfill) VALUES($1,$2,$3,$4,$5,$6)
            ON CONFLICT(device_id,kind,day,tz,algo_version) DO UPDATE SET generation=analysis_jobs.generation+1,available_at=now(),backfill=CASE WHEN analysis_jobs.generation>analysis_jobs.completed_generation THEN analysis_jobs.backfill OR EXCLUDED.backfill ELSE EXCLUDED.backfill END")
            .bind(device).bind(kind).bind(day).bind(tz).bind(version).bind(backfill).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }

    /// Seeds existing history once per device, zone and version pair, transactionally.
    /// # Errors
    /// Database failure; the bootstrap remains retryable.
    pub async fn seed_history(&self, versions: AnalysisVersions) -> StorageResult<()> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        // Serialise bootstrap with another service instance, not with incoming frames.
        sqlx::query("SELECT pg_advisory_xact_lock(742981)")
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        let devices:Vec<(String,String)>=sqlx::query_as("SELECT d.id,coalesce(p.tz,'UTC') FROM devices d LEFT JOIN profiles p ON p.device_id=d.id
            WHERE EXISTS(SELECT 1 FROM samples s WHERE s.device_id=d.id) AND NOT EXISTS
            (SELECT 1 FROM analysis_bootstraps b WHERE b.device_id=d.id AND b.tz=coalesce(p.tz,'UTC') AND b.sleep_version=$1 AND b.workout_version=$2)")
            .bind(versions.sleep).bind(versions.workout).fetch_all(&mut *tx).await.map_err(fail)?;
        for (device, tz) in devices {
            sqlx::query("INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,backfill)
                SELECT $1,'sleep',(ts AT TIME ZONE $2)::date+n,$2,$3,true FROM samples CROSS JOIN generate_series(0,1)n WHERE device_id=$1 GROUP BY 3
                UNION SELECT $1,'workout',(ts AT TIME ZONE $2)::date,$2,$4,true FROM samples WHERE device_id=$1 GROUP BY 3
                ON CONFLICT(device_id,kind,day,tz,algo_version) DO UPDATE SET backfill=true")
                .bind(&device).bind(&tz).bind(versions.sleep).bind(versions.workout).execute(&mut *tx).await.map_err(fail)?;
            sqlx::query("INSERT INTO analysis_bootstraps(device_id,tz,sleep_version,workout_version) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING")
                .bind(&device).bind(&tz).bind(versions.sleep).bind(versions.workout).execute(&mut *tx).await.map_err(fail)?;
        }
        tx.commit().await.map_err(fail)
    }

    /// Atomically claims one job. Sleeping jobs must settle before dependent days.
    /// # Errors
    /// Database failure.
    pub async fn claim_analysis(
        &self,
        versions: AnalysisVersions,
    ) -> StorageResult<Option<AnalysisJob>> {
        sqlx::query_as("WITH candidate AS (
            SELECT j.* FROM analysis_jobs j WHERE generation>completed_generation AND available_at<=now()
            AND (lease_until IS NULL OR lease_until<now())
            AND ((kind='sleep' AND algo_version=$1) OR (kind='workout' AND algo_version=$2)) AND tz=coalesce((SELECT tz FROM profiles p WHERE p.device_id=j.device_id),'UTC')
            AND (kind='sleep' OR NOT EXISTS(SELECT 1 FROM analysis_jobs s WHERE s.device_id=j.device_id AND s.kind='sleep' AND s.algo_version=$1
                AND s.tz=j.tz AND s.generation>s.completed_generation AND s.day<=j.day+1))
            ORDER BY CASE kind WHEN 'sleep' THEN 0 ELSE 1 END, backfill, day DESC
            FOR UPDATE OF j SKIP LOCKED LIMIT 1
        ) UPDATE analysis_jobs j SET claim_id=nextval('analysis_claim_ids'),claimed_generation=j.generation,
            lease_until=now()+interval '10 minutes',attempts=j.attempts+1
        FROM candidate c WHERE (j.device_id,j.kind,j.day,j.tz,j.algo_version)=(c.device_id,c.kind,c.day,c.tz,c.algo_version)
        RETURNING j.device_id,j.kind,j.day,j.tz,j.algo_version,j.generation,j.claim_id,j.backfill")
            .bind(versions.sleep).bind(versions.workout).fetch_optional(self.pool()).await.map_err(fail)
    }

    /// Records a failed attempt with capped backoff; no result is deleted.
    /// # Errors
    /// Database failure.
    pub async fn fail_analysis(&self, job: &AnalysisJob, error: &str) -> StorageResult<()> {
        sqlx::query(
            "UPDATE analysis_jobs SET lease_until=NULL,claim_id=NULL,last_error=$2,
            available_at=now()+make_interval(secs=>least(900,15*power(2,least(attempts,6))))
            WHERE claim_id=$1",
        )
        .bind(job.claim_id)
        .bind(error)
        .execute(self.pool())
        .await
        .map_err(fail)?;
        Ok(())
    }

    /// Publishes a night and queues all potentially affected downstream days.
    /// # Errors
    /// Database failure; the transaction rolls back.
    pub async fn publish_night(
        &self,
        job: &AnalysisJob,
        night: Option<&NewSleep<'_>>,
        inputs: Value,
    ) -> StorageResult<bool> {
        let mut tx = self.pool().begin().await.map_err(fail)?;
        if !fence(&mut tx, job).await? {
            tx.commit().await.map_err(fail)?;
            return Ok(false);
        }
        let before: Option<Value> = sqlx::query_scalar(
            "SELECT metrics FROM sleeps WHERE device_id=$1 AND night_of=$2 AND algo_version=$3",
        )
        .bind(&job.device_id)
        .bind(job.day)
        .bind(job.algo_version)
        .fetch_optional(&mut *tx)
        .await
        .map_err(fail)?;
        if let Some(n) = night {
            sqlx::query("INSERT INTO sleeps(device_id,night_of,algo_version,start_ts,end_ts,stages,metrics) VALUES($1,$2,$3,$4,$5,$6,$7)
                ON CONFLICT(device_id,night_of,algo_version) DO UPDATE SET start_ts=EXCLUDED.start_ts,end_ts=EXCLUDED.end_ts,stages=EXCLUDED.stages,metrics=EXCLUDED.metrics")
                .bind(n.device_id).bind(n.night_of).bind(n.algo_version).bind(n.start_ts).bind(n.end_ts).bind(&n.stages).bind(&n.metrics)
                .execute(&mut *tx).await.map_err(fail)?;
        } else {
            sqlx::query(
                "DELETE FROM sleeps WHERE device_id=$1 AND night_of=$2 AND algo_version=$3",
            )
            .bind(&job.device_id)
            .bind(job.day)
            .bind(job.algo_version)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        }
        if before.as_ref() != night.map(|n| &n.metrics) {
            sqlx::query("UPDATE analysis_jobs SET generation=generation+1,available_at=least(available_at,now()),backfill=backfill OR $3
                WHERE device_id=$1 AND kind='workout' AND day >= $2-1")
                .bind(&job.device_id).bind(job.day).bind(job.backfill).execute(&mut *tx).await.map_err(fail)?;
        }
        complete(&mut tx, job, inputs).await?;
        tx.commit().await.map_err(fail)?;
        Ok(true)
    }

    /// Publishes sessions, day load and completion as a single unit, including empty results.
    /// # Errors
    /// Database failure; the transaction rolls back.
    pub async fn publish_day(
        &self,
        job: &AnalysisJob,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
        workouts: &[NewWorkout<'_>],
        strain: Option<&NewStrain<'_>>,
        inputs: Value,
    ) -> StorageResult<bool> {
        self.publish_day_sessions(
            job,
            DayPublication {
                from,
                to,
                workouts,
                strain,
                inputs,
                sessions: None,
            },
        )
        .await
    }

    /// Publishes the effective correction projection under the same input fence.
    /// # Errors
    /// Database failure; the complete publication rolls back.
    pub async fn publish_day_sessions(
        &self,
        job: &AnalysisJob,
        publication: DayPublication<'_>,
    ) -> StorageResult<bool> {
        let DayPublication {
            from,
            to,
            workouts,
            strain,
            inputs,
            sessions,
        } = publication;
        let mut tx = self.pool().begin().await.map_err(fail)?;
        crate::session_store::lock_device(&mut tx, &job.device_id).await?;
        if !fence(&mut tx, job).await? {
            tx.commit().await.map_err(fail)?;
            return Ok(false);
        }
        let keep: Vec<_> = workouts.iter().map(|w| w.start_ts).collect();
        sqlx::query("DELETE FROM workouts WHERE device_id=$1 AND algo_version=$2 AND start_ts >= $3 AND start_ts < $4 AND start_ts <> ALL($5)")
            .bind(&job.device_id).bind(job.algo_version).bind(from).bind(to).bind(&keep).execute(&mut *tx).await.map_err(fail)?;
        for w in workouts {
            sqlx::query("INSERT INTO workouts(device_id,algo_version,start_ts,end_ts,kind,load,avg_hr,max_hr,trimp,zones_min,kcal,steps,auto_detected,notification_eligible)
                VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,true,$13)
                ON CONFLICT(device_id,algo_version,start_ts) DO UPDATE SET end_ts=EXCLUDED.end_ts,kind=EXCLUDED.kind,load=EXCLUDED.load,avg_hr=EXCLUDED.avg_hr,
                max_hr=EXCLUDED.max_hr,trimp=EXCLUDED.trimp,zones_min=EXCLUDED.zones_min,kcal=EXCLUDED.kcal,steps=EXCLUDED.steps")
                .bind(w.device_id).bind(w.algo_version).bind(w.start_ts).bind(w.end_ts).bind(w.kind).bind(w.load).bind(w.avg_hr)
                .bind(w.max_hr).bind(w.trimp).bind(&w.zones_min).bind(w.kcal).bind(w.steps)
                .bind(!job.backfill && w.end_ts>Utc::now()-chrono::Duration::hours(24))
                .execute(&mut *tx).await.map_err(fail)?;
        }
        if let Some(s) = strain {
            sqlx::query("INSERT INTO strains(device_id,day,algo_version,load,trimp,zones_min,kcal) VALUES($1,$2,$3,$4,$5,$6,$7)
                ON CONFLICT(device_id,day,algo_version) DO UPDATE SET load=EXCLUDED.load,trimp=EXCLUDED.trimp,zones_min=EXCLUDED.zones_min,kcal=EXCLUDED.kcal")
                .bind(s.device_id).bind(s.day).bind(s.algo_version).bind(s.load).bind(s.trimp).bind(&s.zones_min).bind(s.kcal)
                .execute(&mut *tx).await.map_err(fail)?;
        } else {
            sqlx::query("DELETE FROM strains WHERE device_id=$1 AND day=$2 AND algo_version=$3")
                .bind(&job.device_id)
                .bind(job.day)
                .bind(job.algo_version)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
        }
        if let Some(sessions) = sessions {
            crate::session_store::publish_domain_sessions(
                &mut tx,
                crate::SessionDomain::Workout,
                job,
                from,
                to,
                sessions,
            )
            .await?;
        }
        sqlx::query("SELECT project_health_steps($1,$2,$3)")
            .bind(&job.device_id)
            .bind(from)
            .bind(to)
            .execute(&mut *tx)
            .await
            .map_err(fail)?;
        complete(&mut tx, job, inputs).await?;
        tx.commit().await.map_err(fail)?;
        Ok(true)
    }

    /// Heartbeats distinguish a listening HTTP server from a working pipeline.
    /// # Errors
    /// Database failure.
    pub async fn worker_heartbeat(
        &self,
        name: &str,
        error: Option<&str>,
        paused: bool,
    ) -> StorageResult<()> {
        sqlx::query("INSERT INTO worker_status(name,last_success,last_error,paused) VALUES($1,CASE WHEN $2::text IS NULL THEN now() END,$2,$3)
            ON CONFLICT(name) DO UPDATE SET heartbeat_at=now(),last_success=CASE WHEN $2 IS NULL THEN now() ELSE worker_status.last_success END,last_error=$2,paused=$3")
            .bind(name).bind(error).bind(paused).execute(self.pool()).await.map_err(fail)?;
        Ok(())
    }
    /// Returns processing lag without treating the newest timestamp as a cursor.
    /// # Errors
    /// Database failure.
    pub async fn processing_status(
        &self,
        device: &str,
        proto: i32,
        versions: AnalysisVersions,
    ) -> StorageResult<ProcessingStatus> {
        sqlx::query_as("SELECT
            (SELECT count(*) FROM raw_frames WHERE device_id=$1 AND (decoded_proto IS NULL OR decoded_proto<$2)) pending_decode,
            (SELECT count(*) FROM raw_frames WHERE device_id=$1 AND decode_status='failed') decode_failures,
            count(*) FILTER(WHERE generation>completed_generation) pending_analysis,
            count(*) FILTER(WHERE generation>completed_generation AND last_error IS NOT NULL) failed_analysis,
            min(day) FILTER(WHERE generation>completed_generation) oldest_pending_day,max(completed_at) last_analyzed_at,
            (SELECT count(*)=2 AND coalesce(bool_and(heartbeat_at>now()-interval '2 minutes' AND last_error IS NULL),false) FROM worker_status WHERE name IN ('decoder','analysis')) workers_healthy,
            (SELECT coalesce(bool_or(paused),false) FROM worker_status) paused
            FROM analysis_jobs j WHERE device_id=$1 AND ((kind='sleep' AND algo_version=$3) OR (kind='workout' AND algo_version=$4)) AND tz=coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC')")
            .bind(device).bind(proto).bind(versions.sleep).bind(versions.workout).fetch_one(self.pool()).await.map_err(fail)
    }
}

pub(crate) async fn fence(tx: &mut PgConnection, job: &AnalysisJob) -> StorageResult<bool> {
    let valid: Option<bool> = sqlx::query_scalar(
        "SELECT generation=$2 AND lease_until>now() AND
        tz=coalesce((SELECT tz FROM profiles WHERE device_id=j.device_id),'UTC')
        FROM analysis_jobs j WHERE claim_id=$1 FOR UPDATE",
    )
    .bind(job.claim_id)
    .bind(job.generation)
    .fetch_optional(&mut *tx)
    .await
    .map_err(fail)?;
    if valid != Some(true) {
        sqlx::query("UPDATE analysis_jobs SET lease_until=NULL,claim_id=NULL WHERE claim_id=$1")
            .bind(job.claim_id)
            .execute(tx)
            .await
            .map_err(fail)?;
    }
    Ok(valid == Some(true))
}
pub(crate) async fn complete(
    tx: &mut PgConnection,
    job: &AnalysisJob,
    inputs: Value,
) -> StorageResult<()> {
    sqlx::query("UPDATE analysis_jobs SET completed_generation=$2,completed_at=now(),last_error=NULL,attempts=0,
        lease_until=NULL,claim_id=NULL,backfill=false,inputs=$3 WHERE claim_id=$1")
        .bind(job.claim_id).bind(job.generation).bind(inputs).execute(tx).await.map_err(fail)?;
    Ok(())
}

/// Invalidates all periods whose inputs can include a changed sample. Must share the
/// transaction that changed the decoded sample and its frame marker.
pub(crate) async fn queue_samples(
    tx: &mut PgConnection,
    device: &str,
    times: &[DateTime<Utc>],
    v: AnalysisVersions,
) -> StorageResult<()> {
    sqlx::query("WITH z AS(SELECT coalesce((SELECT tz FROM profiles WHERE device_id=$1),'UTC') tz),
        changed AS(SELECT unnest($2::timestamptz[]) at), targets AS (
        SELECT 'sleep' kind,(at AT TIME ZONE z.tz)::date+n AS day,z.tz,$3::int version,at FROM changed,z,generate_series(-1,1)n
        UNION ALL SELECT 'workout',(at AT TIME ZONE z.tz)::date+n,z.tz,$4,at FROM changed,z,generate_series(-1,1) n
        UNION ALL SELECT j.kind,j.day,j.tz,j.algo_version,at FROM analysis_jobs j,changed WHERE j.device_id=$1 AND j.kind='workout' AND j.algo_version=$4
            AND j.day BETWEEN (at AT TIME ZONE j.tz)::date AND (at AT TIME ZONE j.tz)::date+90
    ) INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,available_at,backfill)
        SELECT $1,kind,day,tz,version,now()+interval '30 seconds',bool_and(at<now()-interval '24 hours') FROM targets GROUP BY kind,day,tz,version ORDER BY kind,day,tz,version
        ON CONFLICT(device_id,kind,day,tz,algo_version) DO UPDATE SET generation=analysis_jobs.generation+1,
        backfill=CASE WHEN analysis_jobs.generation>analysis_jobs.completed_generation THEN analysis_jobs.backfill OR EXCLUDED.backfill ELSE EXCLUDED.backfill END,
        available_at=CASE WHEN analysis_jobs.generation=analysis_jobs.completed_generation THEN now()+interval '30 seconds' ELSE analysis_jobs.available_at END")
        .bind(device).bind(times).bind(v.sleep).bind(v.workout).execute(tx).await.map_err(fail)?;
    Ok(())
}

/// All projections of a day share one generation and publication transaction.
#[derive(Debug)]
pub struct DayPublication<'a> {
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    pub workouts: &'a [NewWorkout<'a>],
    pub strain: Option<&'a NewStrain<'a>>,
    pub inputs: Value,
    pub sessions: Option<&'a [crate::SessionCalculation]>,
}
