use std::sync::Arc;

use secrecy::SecretString;
use zoop_storage::PostgresStore;

#[derive(Clone, Debug)]
pub struct AppState {
    pub(crate) setup_token: Option<Arc<SecretString>>,
    pub(crate) web: Option<crate::web::WebOptions>,
    pub(crate) telemetry: Arc<crate::telemetry::Telemetry>,
    pub(crate) share_slots: Arc<tokio::sync::Semaphore>,
    pub(crate) account_write_slots: Arc<tokio::sync::Semaphore>,
    pub(crate) password_slots: Arc<tokio::sync::Semaphore>,
    pub store: PostgresStore,
    pub ingest_token: Arc<SecretString>,
}

impl AppState {
    /// Enable private-account mode; the shared installation token is no longer accepted.
    pub fn with_web(mut self, options: crate::web::WebOptions) -> Self {
        self.web = Some(options);
        self
    }
    /// Enable first-admin setup with a high-entropy operator code.
    pub fn with_setup_token(mut self, token: SecretString) -> Self {
        self.setup_token = Some(Arc::new(token));
        self
    }
    pub fn new(store: PostgresStore, ingest_token: SecretString) -> Self {
        Self {
            web: None,
            setup_token: None,
            telemetry: Arc::default(),
            share_slots: Arc::new(tokio::sync::Semaphore::new(4)),
            account_write_slots: Arc::new(tokio::sync::Semaphore::new(2)),
            password_slots: Arc::new(tokio::sync::Semaphore::new(4)),
            store,
            ingest_token: Arc::new(ingest_token),
        }
    }
}
