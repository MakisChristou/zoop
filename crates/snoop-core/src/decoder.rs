use std::time::Duration;

use chrono::{DateTime, Utc};
use snoop_proto::{Decoded, PROTO_VERSION, Record, decode_frame};
use snoop_storage::{NewEcgStrip, NewSample, PendingFrame, PostgresStore};
use tokio_util::sync::CancellationToken;
use tracing::{debug, info, warn};

use crate::CoreResult;

/// Outcome of one pass over the pending queue.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DecodePass {
    pub frames: usize,
    pub samples: usize,
    pub ecg_strips: usize,
    pub undecodable: usize,
}

#[derive(Debug, Clone)]
pub struct Decoder {
    store: PostgresStore,
    batch_size: i64,
    poll_interval: Duration,
}

impl Decoder {
    pub const fn new(store: PostgresStore, batch_size: i64, poll_interval: Duration) -> Self {
        Self {
            store,
            batch_size,
            poll_interval,
        }
    }

    /// Runs until cancelled. Sleeps `poll_interval` only when a pass found nothing.
    pub async fn run(self, cancel: CancellationToken) -> CoreResult<()> {
        info!(proto = PROTO_VERSION, "decoder running");
        loop {
            let pass = tokio::select! {
                () = cancel.cancelled() => return Ok(()),
                result = self.pass() => result?,
            };
            if pass.frames == 0 {
                tokio::select! {
                    () = cancel.cancelled() => return Ok(()),
                    () = tokio::time::sleep(self.poll_interval) => {}
                }
            }
        }
    }

    /// Decodes one batch of pending frames.
    pub async fn pass(&self) -> CoreResult<DecodePass> {
        let frames = self
            .store
            .fetch_pending_frames(PROTO_VERSION, self.batch_size)
            .await?;
        let mut pass = DecodePass::default();

        for frame in &frames {
            self.decode_one(frame, &mut pass).await?;
            self.store
                .mark_frame_decoded(frame.id, PROTO_VERSION)
                .await?;
            pass.frames += 1;
        }

        if pass.frames > 0 {
            debug!(?pass, "decode pass complete");
        }
        Ok(pass)
    }

    async fn decode_one(&self, frame: &PendingFrame, pass: &mut DecodePass) -> CoreResult<()> {
        let decoded = match decode_frame(&frame.bytes) {
            Ok(decoded) => decoded,
            Err(error) => {
                warn!(frame_id = frame.id, %error, "stored frame failed to decode");
                pass.undecodable += 1;
                return Ok(());
            }
        };
        let Decoded::Record { record, .. } = decoded else {
            return Ok(());
        };

        match record {
            Record::Biometric(biometric) => {
                let ts = DateTime::<Utc>::from_timestamp(i64::from(biometric.unix_seconds), 0)
                    .unwrap_or(frame.received_at);
                let rr_ms = biometric
                    .heart_rate
                    .rr_ms
                    .iter()
                    .map(|&rr| i32::try_from(rr).unwrap_or(i32::MAX))
                    .collect();
                self.store
                    .upsert_sample(&NewSample {
                        device_id: &frame.device_id,
                        ts,
                        hr: Some(i16::from(biometric.heart_rate.bpm)),
                        rr_ms,
                        skin_temp_c: biometric.skin_temp_c,
                        steps: biometric.steps.map(i32::from),
                        accel_dyn_g: biometric.dynamic_accel_g,
                        activity: biometric.activity.map(i16::from),
                        quality: biometric.quality_flags.map(i16::from),
                        raw_frame_id: frame.id,
                    })
                    .await?;
                pass.samples += 1;
            }
            Record::Ecg(ecg) => {
                // The ECG record's own clock word is not yet mapped to wall time;
                // the phone's receipt time is the best anchor available.
                self.store
                    .insert_ecg_strip(&NewEcgStrip {
                        device_id: &frame.device_id,
                        ts: frame.received_at,
                        layout: i16::from(ecg.layout),
                        quality: Some(i16::from(ecg.quality)),
                        samples: ecg.samples.clone(),
                        raw_frame_id: frame.id,
                    })
                    .await?;
                pass.ecg_strips += 1;
            }
            // R20/R21/R26 and unknown layouts stay raw until their decoders are
            // promoted; nothing is lost.
            _ => {}
        }
        Ok(())
    }
}
