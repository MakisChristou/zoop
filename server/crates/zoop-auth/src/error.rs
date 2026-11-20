//! Secret-free credential errors.
/// Safe credential errors without secret values.
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    /// Passwords are bounded to prevent unbounded work.
    #[error("password must contain 12 to 256 bytes")]
    PasswordLength,
    /// Cryptographic operation failed.
    #[error("credential operation failed")]
    Crypto,
}
