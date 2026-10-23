//! GATT identifiers for the WHOOP 5.0 / MG custom service.

pub const SERVICE: &str = "fd4b0001-cce1-4033-93ce-002d5875f58a";
pub const CMD_WRITE: &str = "fd4b0002-cce1-4033-93ce-002d5875f58a";
pub const NOTIFY_CMD_RESPONSE: &str = "fd4b0003-cce1-4033-93ce-002d5875f58a";
pub const NOTIFY_EVENTS: &str = "fd4b0004-cce1-4033-93ce-002d5875f58a";
pub const NOTIFY_DATA: &str = "fd4b0005-cce1-4033-93ce-002d5875f58a";
pub const NOTIFY_MEMFAULT: &str = "fd4b0007-cce1-4033-93ce-002d5875f58a";

/// Standard Device Information Service strings used to tell a 5.0 from an MG.
pub const DIS_MODEL_NUMBER: &str = "00002a24-0000-1000-8000-00805f9b34fb";
pub const DIS_SERIAL_NUMBER: &str = "00002a25-0000-1000-8000-00805f9b34fb";
/// Standard Heart Rate Measurement; streams without a bond.
pub const HR_MEASUREMENT: &str = "00002a37-0000-1000-8000-00805f9b34fb";

/// Serial prefixes observed on the two variants. Absence of a prefix proves nothing.
pub const SERIAL_PREFIX_MG: &str = "5AM";
pub const SERIAL_PREFIX_5_0: &str = "5AG";
