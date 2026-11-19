use std::time::Duration;

use chrono::{DateTime, Utc};
use tokio_util::sync::CancellationToken;
use tracing::{debug, info, warn};
use zoop_proto::{ActivityClass, BandState, Decoded, EventPayload, PROTO_VERSION, decode_frame};
use zoop_storage::{
    AnalysisVersions, DecodeOutput, DecodedFrame, NewEcgStrip, NewEvent, NewSample, PendingFrame,
    PostgresStore,
};

use crate::CoreResult;

/// Outcome of one pass over the pending queue.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DecodePass {
    pub frames: usize,
    pub samples: usize,
    pub events: usize,
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
                result = self.pass() => match result {
                    Ok(pass) => {self.store.worker_heartbeat("decoder",None,false).await?;pass},
                    Err(error) => {
                        warn!(%error,"decode pass failed; retaining pending work");
                        let _=self.store.worker_heartbeat("decoder",Some(&error.to_string()),false).await;
                        DecodePass::default()
                    }
                },
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

        let decoded: Vec<_> = frames
            .iter()
            .map(|frame| Self::decode_one(frame, &mut pass))
            .collect();
        self.store
            .save_decoded(
                &decoded,
                PROTO_VERSION,
                AnalysisVersions {
                    sleep: zoop_analytics::ALGO_VERSION,
                    workout: zoop_analytics::WORKOUT_ALGO_VERSION,
                },
            )
            .await?;
        pass.frames = frames.len();

        if pass.frames > 0 {
            debug!(?pass, "decode pass complete");
        }
        Ok(pass)
    }

    fn decode_one<'a>(frame: &'a PendingFrame, pass: &mut DecodePass) -> DecodedFrame<'a> {
        let output = match decode_frame(&frame.bytes) {
            Err(error) => {
                pass.undecodable += 1;
                DecodeOutput::Failed(error.to_string())
            }
            Ok(decoded) => match decoded {
                Decoded::Biometric(b) => {
                    pass.samples += 1;
                    DecodeOutput::Sample(NewSample {
                        device_id: &frame.device_id,
                        ts: strap_time(b.header.unix_s, frame.received_at),
                        hr: Some(i16::from(b.heart_rate)),
                        rr_ms: b.rr_ms.iter().map(|&rr| i32::from(rr)).collect(),
                        skin_temp_c: b.skin_temp_c,
                        steps: Some(i32::from(b.steps)),
                        accel_dyn_g: b.dynamic_accel_g,
                        gravity_g: b.gravity_g,
                        activity: activity_code(b.activity),
                        band_state: band_state_code(b.band_state),
                        spo2_pct: b.spo2_percent.map(i16::from),
                        raw_frame_id: frame.id,
                    })
                }
                Decoded::Event(e) => {
                    pass.events += 1;
                    let payload = match e.payload {
                        EventPayload::Raw { bytes } => bytes,
                        EventPayload::BatteryLevel(level) => {
                            let mut b = vec![level.revision];
                            b.extend_from_slice(&level.soc_tenths.to_le_bytes());
                            b.extend_from_slice(&[0, 0]);
                            b.extend_from_slice(&level.millivolts.to_le_bytes());
                            b
                        }
                    };
                    DecodeOutput::Event(NewEvent {
                        device_id: &frame.device_id,
                        ts: strap_time(e.unix_s, frame.received_at),
                        event_code: i16::from(e.code),
                        payload,
                        raw_frame_id: frame.id,
                    })
                }
                Decoded::Ecg(e) => {
                    pass.ecg_strips += 1;
                    DecodeOutput::Ecg(NewEcgStrip {
                        device_id: &frame.device_id,
                        ts: strap_time(e.header.unix_s, frame.received_at),
                        layout: i16::from(e.header.layout.as_byte()),
                        quality: Some(i16::from(e.quality)),
                        samples: e.samples,
                        raw_frame_id: frame.id,
                    })
                }
                _ => DecodeOutput::Unsupported,
            },
        };
        DecodedFrame {
            frame_id: frame.id,
            device_id: &frame.device_id,
            output,
        }
    }
}

/// The strap clock, unless it is unset (an `RTC_LOST` strap reports epoch-ish values).
fn strap_time(unix_s: u32, fallback: DateTime<Utc>) -> DateTime<Utc> {
    const PLAUSIBLE_AFTER: i64 = 1_600_000_000; // 2020-09-13
    let seconds = i64::from(unix_s);
    if seconds < PLAUSIBLE_AFTER {
        return fallback;
    }
    DateTime::<Utc>::from_timestamp(seconds, 0).unwrap_or(fallback)
}

const fn activity_code(activity: ActivityClass) -> Option<i16> {
    match activity {
        ActivityClass::Still => Some(0),
        ActivityClass::Walk => Some(1),
        ActivityClass::Run => Some(2),
        ActivityClass::Other(_) => None,
    }
}

const fn band_state_code(state: BandState) -> i16 {
    match state {
        BandState::Wake => 0,
        BandState::Still => 1,
        BandState::Sleep => 2,
        BandState::Up => 3,
    }
}
