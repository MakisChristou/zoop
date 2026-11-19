//! Transactional decoding: data, invalidation and the decode marker advance together.
use crate::analysis_store::queue_samples;
use crate::{
    AnalysisVersions, NewEcgStrip, NewEvent, NewSample, PostgresStore, StorageError, StorageResult,
    StoreOperation,
};

/// One frame's semantic output. Unsupported and malformed payloads remain stored raw.
#[derive(Debug)]
pub enum DecodeOutput<'a> {
    Sample(NewSample<'a>),
    Event(NewEvent<'a>),
    Ecg(NewEcgStrip<'a>),
    Unsupported,
    Failed(String),
}
/// Decode output plus its durable source identity.
#[derive(Debug)]
pub struct DecodedFrame<'a> {
    pub frame_id: i64,
    pub device_id: &'a str,
    pub output: DecodeOutput<'a>,
}

impl PostgresStore {
    /// Commits a complete decode batch and the affected analysis periods atomically.
    /// # Errors
    /// Any database error rolls back all outputs and markers in this batch.
    pub async fn save_decoded(
        &self,
        frames: &[DecodedFrame<'_>],
        proto: i32,
        versions: AnalysisVersions,
    ) -> StorageResult<()> {
        let fail = |e| StorageError::unavailable(StoreOperation::UpsertSample, e);
        let mut tx = self.pool().begin().await.map_err(fail)?;
        let mut affected = std::collections::BTreeSet::new();
        for frame in frames {
            let current: Option<i32> =
                sqlx::query_scalar("SELECT decoded_proto FROM raw_frames WHERE id=$1 FOR UPDATE")
                    .bind(frame.frame_id)
                    .fetch_one(&mut *tx)
                    .await
                    .map_err(fail)?;
            if current.is_some_and(|v| v >= proto) {
                continue;
            }
            let previous: Option<chrono::DateTime<chrono::Utc>> =
                sqlx::query_scalar("SELECT ts FROM samples WHERE raw_frame_id=$1")
                    .bind(frame.frame_id)
                    .fetch_optional(&mut *tx)
                    .await
                    .map_err(fail)?;
            if let Some(at) = previous {
                affected.insert((frame.device_id, at));
            }
            // A protocol fix may change a record's kind or timestamp. Only derived rows are replaced.
            sqlx::query("DELETE FROM samples WHERE raw_frame_id=$1")
                .bind(frame.frame_id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
            sqlx::query("DELETE FROM events WHERE raw_frame_id=$1")
                .bind(frame.frame_id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
            sqlx::query("DELETE FROM ecg_strips WHERE raw_frame_id=$1")
                .bind(frame.frame_id)
                .execute(&mut *tx)
                .await
                .map_err(fail)?;
            match &frame.output {
                DecodeOutput::Sample(s) => {
                    sqlx::query("INSERT INTO samples(device_id,ts,hr,rr_ms,skin_temp_c,steps,accel_dyn_g,gravity_x,gravity_y,gravity_z,activity,band_state,spo2_pct,raw_frame_id)
                    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) ON CONFLICT(device_id,ts) DO UPDATE SET
                    hr=EXCLUDED.hr,rr_ms=EXCLUDED.rr_ms,skin_temp_c=EXCLUDED.skin_temp_c,steps=EXCLUDED.steps,accel_dyn_g=EXCLUDED.accel_dyn_g,
                    gravity_x=EXCLUDED.gravity_x,gravity_y=EXCLUDED.gravity_y,gravity_z=EXCLUDED.gravity_z,activity=EXCLUDED.activity,band_state=EXCLUDED.band_state,spo2_pct=EXCLUDED.spo2_pct,raw_frame_id=EXCLUDED.raw_frame_id
                    WHERE samples.raw_frame_id<=EXCLUDED.raw_frame_id")
                        .bind(s.device_id).bind(s.ts).bind(s.hr).bind(&s.rr_ms).bind(s.skin_temp_c).bind(s.steps).bind(s.accel_dyn_g)
                        .bind(s.gravity_g.map(|g|g[0])).bind(s.gravity_g.map(|g|g[1])).bind(s.gravity_g.map(|g|g[2]))
                        .bind(s.activity).bind(s.band_state).bind(s.spo2_pct).bind(s.raw_frame_id).execute(&mut *tx).await.map_err(fail)?;
                    affected.insert((s.device_id, s.ts));
                }
                DecodeOutput::Event(e) => {
                    sqlx::query("INSERT INTO events(device_id,ts,event_code,payload,raw_frame_id) VALUES($1,$2,$3,$4,$5) ON CONFLICT(raw_frame_id) DO UPDATE SET ts=EXCLUDED.ts,event_code=EXCLUDED.event_code,payload=EXCLUDED.payload")
                    .bind(e.device_id).bind(e.ts).bind(e.event_code).bind(&e.payload).bind(e.raw_frame_id).execute(&mut *tx).await.map_err(fail)?;
                }
                DecodeOutput::Ecg(e) => {
                    sqlx::query("INSERT INTO ecg_strips(device_id,ts,layout,quality,samples,raw_frame_id) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(raw_frame_id) DO UPDATE SET ts=EXCLUDED.ts,layout=EXCLUDED.layout,quality=EXCLUDED.quality,samples=EXCLUDED.samples")
                    .bind(e.device_id).bind(e.ts).bind(e.layout).bind(e.quality).bind(&e.samples).bind(e.raw_frame_id).execute(&mut *tx).await.map_err(fail)?;
                }
                _ => {}
            }
            let (status, error) = match &frame.output {
                DecodeOutput::Failed(e) => ("failed", Some(e.as_str())),
                DecodeOutput::Unsupported => ("unsupported", None),
                _ => ("decoded", None),
            };
            sqlx::query("UPDATE raw_frames SET decoded_proto=$2,decode_status=$3,decode_error=$4 WHERE id=$1")
                .bind(frame.frame_id).bind(proto).bind(status).bind(error).execute(&mut *tx).await.map_err(fail)?;
        }
        // Group exact timestamps per device. Rounding to UTC hours would miss
        // local midnight in time zones with half-hour or quarter-hour offsets.
        let mut devices =
            std::collections::BTreeMap::<&str, Vec<chrono::DateTime<chrono::Utc>>>::new();
        for (device, at) in affected {
            devices.entry(device).or_default().push(at);
        }
        for (device, times) in devices {
            queue_samples(&mut tx, device, &times, versions).await?;
        }
        tx.commit().await.map_err(fail)
    }
}
