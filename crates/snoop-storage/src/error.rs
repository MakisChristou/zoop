use crate::StoreOperation;

type BoxError = Box<dyn std::error::Error + Send + Sync + 'static>;

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("{0}")]
    InvalidCorrection(String),
    #[error("{0}")]
    CorrectionConflict(String),
    #[error("no such workout or correction")]
    CorrectionNotFound,
    #[error("storage unavailable while attempting to {operation}: {source}")]
    Unavailable {
        operation: StoreOperation,
        #[source]
        source: BoxError,
    },
    #[error("invalid storage data while attempting to {operation}: {message}")]
    InvalidData {
        operation: StoreOperation,
        message: String,
    },
}

impl StorageError {
    pub(crate) fn unavailable(
        operation: StoreOperation,
        source: impl std::error::Error + Send + Sync + 'static,
    ) -> Self {
        Self::Unavailable {
            operation,
            source: Box::new(source),
        }
    }

    pub(crate) fn invalid_data(operation: StoreOperation, message: impl Into<String>) -> Self {
        Self::InvalidData {
            operation,
            message: message.into(),
        }
    }
}

pub type StorageResult<T> = Result<T, StorageError>;
