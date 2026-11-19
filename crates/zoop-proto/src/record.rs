//! Sensor records carried by packet types 43 (live) and 47 (stored history).
//!
//! Every record starts with the same header at frame offsets 8..21; byte 9 selects
//! the layout. Only the layouts zoop needs today are decoded; the others are kept
//! whole as `UnknownRecord` so nothing is lost.

use crate::{Frame, ProtoError, ProtoResult};

/// Record layout selector, frame byte 9.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum Layout {
    /// MG raw ECG, 18-bit samples.
    EcgRaw,
    /// MG filtered ECG, i16 samples.
    EcgFiltered,
    /// 1 Hz biometric summary: HR, R-R, motion, temperature, band state.
    Biometric,
    /// Optical blocks.
    Optical,
    /// Six-axis IMU.
    Imu,
    /// High-rate v9 channels.
    V9,
    /// Compact optical window.
    CompactOptical,
    Unknown(u8),
}

impl Layout {
    pub const ECG_RAW: u8 = 16;
    pub const ECG_FILTERED: u8 = 17;
    pub const BIOMETRIC: u8 = 18;
    pub const OPTICAL: u8 = 20;
    pub const IMU: u8 = 21;
    pub const V9_CHANNELS: u8 = 22;
    pub const COMPACT_OPTICAL: u8 = 26;

    pub const fn from_byte(byte: u8) -> Self {
        match byte {
            Self::ECG_RAW => Self::EcgRaw,
            Self::ECG_FILTERED => Self::EcgFiltered,
            Self::BIOMETRIC => Self::Biometric,
            Self::OPTICAL => Self::Optical,
            Self::IMU => Self::Imu,
            Self::V9_CHANNELS => Self::V9,
            Self::COMPACT_OPTICAL => Self::CompactOptical,
            other => Self::Unknown(other),
        }
    }

    pub const fn as_byte(self) -> u8 {
        match self {
            Self::EcgRaw => Self::ECG_RAW,
            Self::EcgFiltered => Self::ECG_FILTERED,
            Self::Biometric => Self::BIOMETRIC,
            Self::Optical => Self::OPTICAL,
            Self::Imu => Self::IMU,
            Self::V9 => Self::V9_CHANNELS,
            Self::CompactOptical => Self::COMPACT_OPTICAL,
            Self::Unknown(byte) => byte,
        }
    }

    /// Fixed total frame length for layouts with one; a mismatch means the bytes
    /// are not this layout, not a layout with fields missing.
    pub const fn frame_len(self) -> Option<usize> {
        match self {
            Self::EcgRaw => Some(1584),
            Self::EcgFiltered => Some(240),
            Self::Biometric => Some(124),
            Self::Optical => Some(2140),
            Self::Imu => Some(1244),
            Self::CompactOptical => Some(88),
            Self::V9 | Self::Unknown(_) => None,
        }
    }
}

/// Common record header, frame offsets 8..21.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct RecordHeader {
    pub layout: Layout,
    pub marker: u8,
    /// The strap's own record counter. Not a timestamp.
    pub record_index: u32,
    pub unix_s: u32,
    pub subsec: u16,
}

impl RecordHeader {
    pub const LAYOUT_OFFSET: usize = 9;
    const MARKER_OFFSET: usize = 10;
    const RECORD_INDEX_OFFSET: usize = 11;
    const UNIX_OFFSET: usize = 15;
    const SUBSEC_OFFSET: usize = 19;

    pub(crate) fn parse(frame: &Frame<'_>) -> ProtoResult<Self> {
        Ok(Self {
            layout: Layout::from_byte(frame.u8_at(Self::LAYOUT_OFFSET)?),
            marker: frame.u8_at(Self::MARKER_OFFSET)?,
            record_index: frame.u32_at(Self::RECORD_INDEX_OFFSET)?,
            unix_s: frame.u32_at(Self::UNIX_OFFSET)?,
            subsec: frame.u16_at(Self::SUBSEC_OFFSET)?,
        })
    }
}

/// The strap's own motion/rest classification, R18 state bits 4..6.
/// `Sleep` is WHOOP's on-device rest flag, not a sleep stage.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum BandState {
    Wake,
    Still,
    Sleep,
    Up,
}

impl BandState {
    const SHIFT: u8 = 4;
    const MASK: u8 = 0b11;

    pub const fn from_state_bits(bits: u8) -> Self {
        match (bits >> Self::SHIFT) & Self::MASK {
            0 => Self::Wake,
            1 => Self::Still,
            2 => Self::Sleep,
            _ => Self::Up,
        }
    }

    pub const fn to_state_bits(self) -> u8 {
        let value: u8 = match self {
            Self::Wake => 0,
            Self::Still => 1,
            Self::Sleep => 2,
            Self::Up => 3,
        };
        value << Self::SHIFT
    }
}

/// Coarse activity class, R18 byte 63. Anything else on the wire is `Other`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum ActivityClass {
    Still,
    Walk,
    Run,
    Other(u8),
}

impl ActivityClass {
    pub const fn from_byte(byte: u8) -> Self {
        match byte {
            0 => Self::Still,
            1 => Self::Walk,
            2 => Self::Run,
            other => Self::Other(other),
        }
    }
}

/// R18 biometric summary, one per second. 124-byte frame.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Biometric {
    pub header: RecordHeader,
    pub heart_rate: u8,
    /// R-R intervals in milliseconds, zero placeholders removed.
    pub rr_ms: Vec<u16>,
    pub hr_flags: u8,
    pub alt_heart_rate: u8,
    pub dynamic_accel_g: Option<f32>,
    pub gravity_g: Option<[f32; 3]>,
    pub steps: u16,
    pub cadence_raw: u16,
    pub hw_steps: u16,
    pub activity: ActivityClass,
    /// Auxiliary temperatures, 0.1 °C units; `None` outside 0..=60 °C.
    pub temp_aux1_c: Option<f32>,
    pub temp_aux2_c: Option<f32>,
    /// Skin temperature, 0.01 °C units; `None` outside 5..=45 °C.
    pub skin_temp_c: Option<f32>,
    pub status_words: [u16; 3],
    pub state_bits: u8,
    pub band_state: BandState,
    /// SpO₂ percentage when byte 82 holds a valid reading (70..=100). The strap
    /// measures in 30 s windows every 20 min during sleep; otherwise this is `None`.
    pub spo2_percent: Option<u8>,
    pub spo2_raw: u8,
}

impl Biometric {
    pub const HR_OFFSET: usize = 22;
    pub const RR_COUNT_OFFSET: usize = 23;
    pub const RR_OFFSET: usize = 24;
    pub const RR_MAX: usize = 4;
    pub const HR_FLAGS_OFFSET: usize = 36;
    pub const ALT_HR_OFFSET: usize = 37;
    pub const DYN_ACCEL_OFFSET: usize = 41;
    pub const GRAVITY_OFFSET: usize = 45;
    pub const STEPS_OFFSET: usize = 57;
    pub const CADENCE_OFFSET: usize = 59;
    pub const HW_STEPS_OFFSET: usize = 61;
    pub const ACTIVITY_OFFSET: usize = 63;
    pub const TEMP_AUX1_OFFSET: usize = 69;
    pub const TEMP_AUX2_OFFSET: usize = 71;
    pub const SKIN_TEMP_OFFSET: usize = 73;
    pub const STATUS_WORDS_OFFSET: usize = 75;
    pub const STATE_BITS_OFFSET: usize = 81;
    pub const SPO2_OFFSET: usize = 82;

    const SPO2_VALID: std::ops::RangeInclusive<u8> = 70..=100;
    const AUX_TEMP_VALID_C: std::ops::RangeInclusive<f32> = 0.0..=60.0;
    const SKIN_TEMP_VALID_C: std::ops::RangeInclusive<f32> = 5.0..=45.0;
    const DYN_ACCEL_VALID_G: std::ops::RangeInclusive<f32> = 0.0..=8.0;

    pub(crate) fn parse(frame: &Frame<'_>, header: RecordHeader) -> ProtoResult<Self> {
        let rr_count = usize::from(frame.u8_at(Self::RR_COUNT_OFFSET)?).min(Self::RR_MAX);
        let mut rr_ms = Vec::with_capacity(rr_count);
        for i in 0..rr_count {
            let rr = frame.u16_at(Self::RR_OFFSET + i * 2)?;
            if rr != 0 {
                rr_ms.push(rr);
            }
        }

        let dynamic_accel_g = Some(frame.f32_at(Self::DYN_ACCEL_OFFSET)?)
            .filter(|g| g.is_finite() && Self::DYN_ACCEL_VALID_G.contains(g));
        let gravity = [
            frame.f32_at(Self::GRAVITY_OFFSET)?,
            frame.f32_at(Self::GRAVITY_OFFSET + 4)?,
            frame.f32_at(Self::GRAVITY_OFFSET + 8)?,
        ];
        let gravity_g = gravity.iter().all(|g| g.is_finite()).then_some(gravity);

        let aux_temp = |offset| -> ProtoResult<Option<f32>> {
            let celsius = f32::from(frame.i16_at(offset)?) / 10.0;
            Ok(Some(celsius).filter(|c| Self::AUX_TEMP_VALID_C.contains(c)))
        };
        let skin_temp_c = Some(f32::from(frame.u16_at(Self::SKIN_TEMP_OFFSET)?) / 100.0)
            .filter(|c| Self::SKIN_TEMP_VALID_C.contains(c));

        let state_bits = frame.u8_at(Self::STATE_BITS_OFFSET)?;
        let spo2_raw = frame.u8_at(Self::SPO2_OFFSET)?;

        Ok(Self {
            header,
            heart_rate: frame.u8_at(Self::HR_OFFSET)?,
            rr_ms,
            hr_flags: frame.u8_at(Self::HR_FLAGS_OFFSET)?,
            alt_heart_rate: frame.u8_at(Self::ALT_HR_OFFSET)?,
            dynamic_accel_g,
            gravity_g,
            steps: frame.u16_at(Self::STEPS_OFFSET)?,
            cadence_raw: frame.u16_at(Self::CADENCE_OFFSET)?,
            hw_steps: frame.u16_at(Self::HW_STEPS_OFFSET)?,
            activity: ActivityClass::from_byte(frame.u8_at(Self::ACTIVITY_OFFSET)?),
            temp_aux1_c: aux_temp(Self::TEMP_AUX1_OFFSET)?,
            temp_aux2_c: aux_temp(Self::TEMP_AUX2_OFFSET)?,
            skin_temp_c,
            status_words: [
                frame.u16_at(Self::STATUS_WORDS_OFFSET)?,
                frame.u16_at(Self::STATUS_WORDS_OFFSET + 2)?,
                frame.u16_at(Self::STATUS_WORDS_OFFSET + 4)?,
            ],
            state_bits,
            band_state: BandState::from_state_bits(state_bits),
            spo2_percent: Some(spo2_raw).filter(|v| Self::SPO2_VALID.contains(v)),
            spo2_raw,
        })
    }
}

/// MG ECG strip: R16 raw (18-bit samples, up to 500) or R17 filtered (i16, up to 100).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EcgStrip {
    pub header: RecordHeader,
    pub quality: u8,
    pub state_bits: u8,
    pub classifier_result: u8,
    pub classifier_state: u8,
    pub progress: u8,
    pub declared_count: u16,
    /// Raw ADC counts; scale to volts is not established.
    pub samples: Vec<i32>,
    /// R16 only: per-sample flag bit 6.
    pub sample_flags: Vec<bool>,
}

impl EcgStrip {
    const QUALITY_OFFSET: usize = 21;
    const STATE_BITS_OFFSET: usize = 22;
    const CLASSIFIER_RESULT_OFFSET: usize = 23;
    const CLASSIFIER_STATE_OFFSET: usize = 24;
    const PROGRESS_OFFSET: usize = 25;
    const SAMPLE_COUNT_OFFSET: usize = 32;
    const SAMPLE_OFFSET: usize = 34;
    const RAW_CAPACITY: usize = 500;
    const FILTERED_CAPACITY: usize = 100;
    const RAW18_SIGN: i32 = 1 << 17;
    const RAW18_RANGE: i32 = 1 << 18;

    pub(crate) fn parse(frame: &Frame<'_>, header: RecordHeader) -> ProtoResult<Self> {
        let declared_count = frame.u16_at(Self::SAMPLE_COUNT_OFFSET)?;
        let (capacity, width) = match header.layout {
            Layout::EcgRaw => (Self::RAW_CAPACITY, 3),
            _ => (Self::FILTERED_CAPACITY, 2),
        };
        let count = usize::from(declared_count);
        if count > capacity {
            return Err(ProtoError::RecordLength {
                layout: header.layout.as_byte(),
                expected: capacity,
                actual: count,
            });
        }

        let mut samples = Vec::with_capacity(count);
        let mut sample_flags = Vec::new();
        for i in 0..count {
            let offset = Self::SAMPLE_OFFSET + i * width;
            if width == 2 {
                samples.push(i32::from(frame.i16_at(offset)?));
            } else {
                let bytes = frame.inner_bytes(offset, 3)?;
                let raw18 = (i32::from(bytes[0] & 0x03) << 16)
                    | (i32::from(bytes[1]) << 8)
                    | i32::from(bytes[2]);
                let signed = if raw18 >= Self::RAW18_SIGN {
                    raw18 - Self::RAW18_RANGE
                } else {
                    raw18
                };
                samples.push(signed);
                sample_flags.push((bytes[0] >> 6) & 1 == 1);
            }
        }

        Ok(Self {
            header,
            quality: frame.u8_at(Self::QUALITY_OFFSET)?,
            state_bits: frame.u8_at(Self::STATE_BITS_OFFSET)?,
            classifier_result: frame.u8_at(Self::CLASSIFIER_RESULT_OFFSET)?,
            classifier_state: frame.u8_at(Self::CLASSIFIER_STATE_OFFSET)?,
            progress: frame.u8_at(Self::PROGRESS_OFFSET)?,
            declared_count,
            samples,
            sample_flags,
        })
    }
}

/// A record whose layout zoop does not decode yet. The raw frame stays in storage.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct UnknownRecord {
    pub header: RecordHeader,
    pub frame_len: usize,
}
