use std::time::Duration;

use chrono::{DateTime, Utc};
use snoop_proto::{ActivityClass, BandState, Decoded, EventPayload, PROTO_VERSION, decode_frame};
use snoop_storage::{NewEcgStrip, NewEvent, NewSample, PendingFrame, PostgresStore};
use tokio_util::sync::CancellationToken;
use tracing::{debug, info, warn};

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

        match decoded {
            Decoded::Biometric(b) => {
                let rr_ms = b.rr_ms.iter().map(|&rr| i32::from(rr)).collect();
                self.store
                    .upsert_sample(&NewSample {
                        device_id: &frame.device_id,
                        ts: strap_time(b.header.unix_s, frame.received_at),
                        hr: Some(i16::from(b.heart_rate)),
                        rr_ms,
                        skin_temp_c: b.skin_temp_c,
                        steps: Some(i32::from(b.steps)),
                        accel_dyn_g: b.dynamic_accel_g,
                        gravity_g: b.gravity_g,
                        activity: activity_code(b.activity),
                        band_state: band_state_code(b.band_state),
                        spo2_pct: b.spo2_percent.map(i16::from),
                        raw_frame_id: frame.id,
                    })
                    .await?;
                pass.samples += 1;
            }
            Decoded::Event(event) => {
                let payload = match event.payload {
                    EventPayload::Raw { bytes } => bytes,
                    EventPayload::BatteryLevel(level) => {
                        let mut bytes = vec![level.revision];
                        bytes.extend_from_slice(&level.soc_tenths.to_le_bytes());
                        bytes.extend_from_slice(&[0, 0]);
                        bytes.extend_from_slice(&level.millivolts.to_le_bytes());
                        bytes
                    }
                };
                self.store
                    .insert_event(&NewEvent {
                        device_id: &frame.device_id,
                        ts: strap_time(event.unix_s, frame.received_at),
                        event_code: i16::from(event.code),
                        payload,
                        raw_frame_id: frame.id,
                    })
                    .await?;
                pass.events += 1;
            }
            Decoded::Ecg(ecg) => {
                self.store
                    .insert_ecg_strip(&NewEcgStrip {
                        device_id: &frame.device_id,
                        ts: strap_time(ecg.header.unix_s, frame.received_at),
                        layout: i16::from(ecg.header.layout.as_byte()),
                        quality: Some(i16::from(ecg.quality)),
                        samples: ecg.samples,
                        raw_frame_id: frame.id,
                    })
                    .await?;
                pass.ecg_strips += 1;
            }
            // Undecoded layouts, live HR, metadata and command responses stay raw;
            // nothing is lost and they are re-read when the decoder learns them.
            Decoded::UnknownRecord(_)
            | Decoded::RealtimeHr(_)
            | Decoded::Metadata(_)
            | Decoded::CommandResponse(_)
            | Decoded::Other { .. } => {}
        }
        Ok(())
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
