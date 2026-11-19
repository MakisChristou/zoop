//! Password hashing and high-entropy session credentials.
mod credentials;
mod error;
pub use credentials::{digest, hash_password, random_token, verify_password};
pub use error::AuthError;
#[cfg(test)]
mod tests;
