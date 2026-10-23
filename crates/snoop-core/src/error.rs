#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error(transparent)]
    Storage(#[from] snoop_storage::StorageError),
}

pub type CoreResult<T> = Result<T, CoreError>;
