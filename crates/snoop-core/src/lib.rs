//! Background work on top of the store. `Decoder` is the first worker; the night and
//! workout analyzers join it.

mod decoder;
mod error;
mod night;
mod workouts;

pub use decoder::{DecodePass, Decoder};
pub use error::{CoreError, CoreResult};
pub use night::{NightAnalyzer, NightResult, analyze_night, night_epochs};
pub use workouts::{BoutOut, DayResult, DaySteps, WorkoutAnalyzer, analyze_day, day_steps};
