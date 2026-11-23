//! Shared state: no model keys or provider dependency.
use std::sync::Arc;
use zoop_storage::PostgresStore;
/// Agent API state for one configured installation.
#[derive(Clone, Debug)]
pub struct AgentState {
    pub(crate) store: PostgresStore,
    pub(crate) origin: String,
    pub(crate) slots: Arc<tokio::sync::Semaphore>,
}
impl AgentState {
    /// Uses the existing validated browser origin for OAuth metadata, never Host headers.
    pub fn new(store: PostgresStore, origin: String) -> Self {
        Self {
            store,
            origin: origin.trim_end_matches('/').into(),
            slots: Arc::new(tokio::sync::Semaphore::new(2)),
        }
    }
    pub(crate) fn resource(&self) -> String {
        format!("{}/mcp", self.origin)
    }
}
