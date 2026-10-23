//! Background work on top of the store. `Decoder` is the first worker; analytics
//! (sleep, recovery, strain) join it as further workers.

mod decoder;
mod error;

pub use decoder::{DecodePass, Decoder};
pub use error::{CoreError, CoreResult};
