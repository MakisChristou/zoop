use std::sync::Arc;

use secrecy::SecretString;
use snoop_storage::PostgresStore;

#[derive(Clone, Debug)]
pub struct AppState {
    pub store: PostgresStore,
    pub ingest_token: Arc<SecretString>,
}

impl AppState {
    pub fn new(store: PostgresStore, ingest_token: SecretString) -> Self {
        Self {
            store,
            ingest_token: Arc::new(ingest_token),
        }
    }
}
