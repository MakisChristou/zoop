//! Public entry points into the shared session correction engine.
use crate::session_store::SessionStore;
use crate::{
    CorrectionReceipt, CorrectionScope, PostgresStore, SessionDomain, StorageResult,
    WorkoutCorrection, WorkoutSession,
};
use chrono::{DateTime, Utc};
impl PostgresStore {
    /// Selects independently stored sleep or workout sessions.
    pub fn sessions(&self, domain: SessionDomain) -> SessionStore<'_> {
        SessionStore {
            store: self,
            domain,
        }
    }
    /// Workout compatibility entry point.
    /// # Errors
    /// Invalid corrections or database failure.
    pub async fn list_sessions(
        &self,
        device: &str,
        status: &str,
        from: Option<DateTime<Utc>>,
        to: Option<DateTime<Utc>>,
        limit: i64,
    ) -> StorageResult<Vec<WorkoutSession>> {
        self.sessions(SessionDomain::Workout)
            .list_sessions(device, status, from, to, limit)
            .await
    }
    /// Workout compatibility entry point.
    /// # Errors
    /// Invalid corrections or database failure.
    pub async fn get_session(
        &self,
        device: &str,
        id: i64,
    ) -> StorageResult<Option<WorkoutSession>> {
        self.sessions(SessionDomain::Workout)
            .get_session(device, id)
            .await
    }
    /// Workout compatibility entry point.
    /// # Errors
    /// Invalid corrections or database failure.
    pub async fn correction_scopes(
        &self,
        device: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<CorrectionScope>> {
        self.sessions(SessionDomain::Workout)
            .correction_scopes(device, from, to)
            .await
    }
    /// Workout compatibility entry point.
    /// # Errors
    /// Invalid corrections or database failure.
    pub async fn fixed_sessions(
        &self,
        device: &str,
        from: DateTime<Utc>,
        to: DateTime<Utc>,
    ) -> StorageResult<Vec<WorkoutSession>> {
        self.sessions(SessionDomain::Workout)
            .fixed_sessions(device, from, to)
            .await
    }
    /// Workout compatibility entry point.
    /// # Errors
    /// Invalid corrections or database failure.
    pub async fn correct_workout(
        &self,
        device: &str,
        command: &WorkoutCorrection,
        version: i32,
    ) -> StorageResult<CorrectionReceipt> {
        self.sessions(SessionDomain::Workout)
            .correct_workout(device, command, version)
            .await
    }
}
