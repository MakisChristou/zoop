//! snoop TOML configuration.

mod error;
mod load;
mod schema;
mod validation;

#[cfg(test)]
mod tests;

pub use error::{ConfigError, ConfigResult};
pub use schema::*;
pub use validation::{IssueLevel, ValidationIssue};
