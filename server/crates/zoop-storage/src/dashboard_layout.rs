//! Private account/device presentation preferences with optimistic saves.
use crate::{PostgresStore, StorageError, StorageResult, StoreOperation};
use serde_json::Value;
fn fail(e: sqlx::Error) -> StorageError {
    StorageError::unavailable(StoreOperation::Sharing, e)
}
impl PostgresStore {
    /// Reads an owned dashboard layout; absence means the built-in default.
    /// # Errors
    /// Database failure.
    pub async fn dashboard_layout(
        &self,
        owner: i64,
        device: &str,
    ) -> StorageResult<Option<(Value, i64)>> {
        sqlx::query_as("SELECT config,revision FROM dashboard_layouts WHERE account_id=$1 AND device_id=$2 AND EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$2)")
            .bind(owner).bind(device).fetch_optional(self.pool()).await.map_err(fail)
    }
    /// Saves only against the current revision and current ownership. Zero creates.
    /// # Errors
    /// Database failure.
    pub async fn save_dashboard_layout(
        &self,
        owner: i64,
        device: &str,
        config: &Value,
        revision: i64,
    ) -> StorageResult<Option<i64>> {
        if revision == 0 {
            sqlx::query_scalar("INSERT INTO dashboard_layouts(account_id,device_id,config) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$2) ON CONFLICT DO NOTHING RETURNING revision")
                .bind(owner).bind(device).bind(config).fetch_optional(self.pool()).await.map_err(fail)
        } else {
            sqlx::query_scalar("UPDATE dashboard_layouts SET config=$3,revision=revision+1 WHERE account_id=$1 AND device_id=$2 AND revision=$4 AND EXISTS(SELECT 1 FROM device_owners WHERE account_id=$1 AND device_id=$2) RETURNING revision")
                .bind(owner).bind(device).bind(config).bind(revision).fetch_optional(self.pool()).await.map_err(fail)
        }
    }
}
