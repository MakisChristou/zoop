//! Small, explicit permission vocabulary shared by OAuth, keys, REST and MCP.
use crate::{
    error::{AgentError, AgentResult},
    state::AgentState,
};
use serde::Deserialize;
/// Available read scopes. Sleep excludes physiological readings; Recovery includes HRV/RHR.
pub const SCOPES: [&str; 5] = [
    "sleep:read",
    "recovery:read",
    "activity:read",
    "weight:read",
    "goals:read",
];
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Consent {
    pub device_id: String,
    pub name: String,
    pub scopes: Vec<String>,
    #[serde(default = "default_history")]
    pub history_days: Option<i32>,
    pub timezone: String,
    pub expires_in_days: i64,
}
impl Consent {
    pub(crate) async fn validate(&self, s: &AgentState) -> AgentResult<()> {
        if self.name.trim().is_empty()
            || self.name.len() > 80
            || self.name.chars().any(char::is_control)
            || self.device_id.len() > 128
            || self.scopes.is_empty()
            || self.scopes.len() > 5
            || self.scopes.iter().any(|v| !SCOPES.contains(&v.as_str()))
            || self
                .scopes
                .iter()
                .enumerate()
                .any(|(i, v)| self.scopes[..i].contains(v))
            || !matches!(self.history_days, None | Some(30 | 90))
            || !(1..=365).contains(&self.expires_in_days)
            || self.timezone.len() > 64
            || !s.store.agent_timezone_valid(&self.timezone).await?
        {
            return Err(AgentError::Invalid(
                "Choose a name, data access, valid timezone and expiry.",
            ));
        }
        Ok(())
    }
}

fn default_history() -> Option<i32> {
    Some(30)
}
