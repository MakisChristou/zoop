//! Published-method analytics. No WHOOP formulas are reproduced here; each module
//! cites the method it implements. Every output carries `ALGO_VERSION` so the
//! worker can backfill when a method changes.

pub mod baseline;
pub mod bouts;
pub mod energy;
pub mod hrv;
pub mod interval;
pub mod respiration;
pub mod sleep;
pub mod stages;
pub mod workouts;
pub mod zones;

/// Bump on any change that alters the sleep numbers.
pub const ALGO_VERSION: i32 = 2;

/// Bump on any change that alters the workout or day-load numbers. Separate from the
/// sleep version so a change on one side never hides the other side's history.
/// Version 2 evaluates physiological inputs as of the analysed day.
/// Version 3 adds durable corrections and allocates session calories by local day.
pub const WORKOUT_ALGO_VERSION: i32 = 3;
