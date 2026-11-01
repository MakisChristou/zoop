//! Background work on top of the store. `Decoder` is the first worker; the night and
//! workout analyzers join it.

mod decoder;
mod error;
mod history;
mod night;
mod workouts;

pub use decoder::{DecodePass, Decoder};
pub use error::{CoreError, CoreResult};
pub use history::HistoryWorker;
pub use night::{NightResult, analyze_night, night_epochs};
pub use workouts::{BoutOut, DayResult, DaySteps, analyze_day, day_steps};
