#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("invalid calculated projection: {0}")]
    Projection(#[from] serde_json::Error),
    #[error(transparent)]
    Storage(#[from] snoop_storage::StorageError),
}

pub type CoreResult<T> = Result<T, CoreError>;
