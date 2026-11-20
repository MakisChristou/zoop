//! Password hashing and random token primitives.
use crate::AuthError;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::SaltString};
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
/// Hash a password with an independent salt.
/// # Errors
/// Invalid length or unavailable randomness/password hashing.
pub fn hash_password(password: &str) -> Result<String, AuthError> {
    if !(12..=256).contains(&password.len()) {
        return Err(AuthError::PasswordLength);
    }
    let mut salt = [0u8; 16];
    OsRng
        .try_fill_bytes(&mut salt)
        .map_err(|_| AuthError::Crypto)?;
    let salt = SaltString::encode_b64(&salt).map_err(|_| AuthError::Crypto)?;
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|_| AuthError::Crypto)
}
/// Verify a password without exposing parse errors or secret material.
pub fn verify_password(password: &str, hash: &str) -> bool {
    if password.len() > 256 {
        return false;
    }
    PasswordHash::new(hash).is_ok_and(|h| {
        Argon2::default()
            .verify_password(password.as_bytes(), &h)
            .is_ok()
    })
}
/// Digest a high-entropy token before persistence.
pub fn digest(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}
/// Generate a 256-bit credential using the OS random source.
/// # Errors
/// The OS random source is unavailable.
pub fn random_token() -> Result<String, AuthError> {
    let mut bytes = [0u8; 32];
    OsRng
        .try_fill_bytes(&mut bytes)
        .map_err(|_| AuthError::Crypto)?;
    Ok(hex::encode(bytes))
}
