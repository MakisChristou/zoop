//! Background work on top of the store. `Decoder` is the first worker; analytics
//! (sleep, recovery, strain) join it as further workers.

mod decoder;
mod error;
mod night;

pub use decoder::{DecodePass, Decoder};
pub use error::{CoreError, CoreResult};
pub use night::{NightAnalyzer, NightResult, analyze_night, night_epochs};
