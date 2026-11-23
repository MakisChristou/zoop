//! Read-only, individually revocable access for user-chosen agents.
mod auth;
mod clients;
mod connections;
mod data;
mod error;
mod mcp;
mod oauth;
mod openapi;
mod permissions;
mod router;
mod state;
pub use error::{AgentError, AgentResult};
pub use router::router;
pub use state::AgentState;
