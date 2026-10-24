//! Postgres persistence. Raw frames are the durable source of truth; decoded tables
//! are rebuilt from them whenever the protocol version advances.

mod day_store;
mod error;
mod frame_store;
mod operation;
mod sample_store;
mod sleep_store;

pub use day_store::DayRow;
pub use error::{StorageError, StorageResult};
pub use frame_store::{NewRawFrame, PendingFrame};
pub use operation::StoreOperation;
pub use sample_store::{NewEcgStrip, NewEvent, NewSample, SampleRow};
pub use sleep_store::{NewSleep, SampleFull, SleepRow};

use sqlx::{PgPool, postgres::PgPoolOptions};

const MAX_CONNECTIONS: u32 = 8;

#[derive(Debug, Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    /// Connects lazily; the first query opens the connection.
    ///
    /// # Errors
    ///
    /// `url` is not a Postgres URL.
    pub async fn connect(url: &str) -> StorageResult<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(MAX_CONNECTIONS)
            .connect(url)
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::Connect, source))?;
        Ok(Self { pool })
    }

    /// Applies pending embedded migrations.
    ///
    /// # Errors
    ///
    /// The database connection fails, or a migration cannot be applied.
    pub async fn migrate(url: &str) -> StorageResult<()> {
        let store = Self::connect(url).await?;
        sqlx::migrate!("../../migrations")
            .run(&store.pool)
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::Migrate, source))?;
        Ok(())
    }

    pub async fn ping(&self) -> StorageResult<()> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(|source| StorageError::unavailable(StoreOperation::Ping, source))?;
        Ok(())
    }

    const fn pool(&self) -> &PgPool {
        &self.pool
    }
}
