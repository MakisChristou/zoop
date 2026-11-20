//! Background work on top of the store. `Decoder` is the first worker; the night and
//! workout analyzers join it.

mod decoder;
mod error;
mod history;
mod insights;
pub use insights::morning_insights;
mod recovery;
pub use recovery::observe_recovery;
mod night;
mod sleep_sessions;
mod workouts;

pub use decoder::{DecodePass, Decoder};
pub use error::{CoreError, CoreResult};
pub use history::HistoryWorker;
pub use night::{NightResult, analyze_night, night_epochs};
pub use workouts::{BoutOut, DayResult, DaySteps, analyze_day, day_steps};

mod progress;
pub use progress::{Period, Progress, ProgressMetric, progress};

mod weight_outlook;
pub use weight_outlook::{WeightOutlook, WeightWeek, phase_outlook, weight_outlook};

mod cut_progress;
pub use cut_progress::{CutProgress, cut_progress};
