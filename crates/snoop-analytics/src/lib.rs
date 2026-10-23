//! Published-method analytics. No WHOOP formulas are reproduced here; each module
//! cites the method it implements. Every output carries `ALGO_VERSION` so the
//! worker can backfill when a method changes.

pub mod baseline;
pub mod hrv;

/// Bump on any change that alters computed numbers.
pub const ALGO_VERSION: i32 = 1;
