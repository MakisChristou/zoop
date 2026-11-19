//! Query-parameter helpers shared by the read handlers.

use crate::error::ApiError;

const MAX_TZ_LEN: usize = 64;

pub(crate) fn default_tz() -> String {
    "UTC".to_owned()
}

/// Accepts IANA zone names such as `Europe/Nicosia` or `Etc/GMT+3`. Postgres has the
/// final say; this only keeps junk out of the query.
pub(crate) fn validate_tz(tz: &str) -> Result<(), ApiError> {
    if tz.is_empty()
        || tz.len() > MAX_TZ_LEN
        || !tz
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "/_+-".contains(c))
    {
        return Err(ApiError::BadRequest("invalid tz".to_owned()));
    }
    Ok(())
}
