#![allow(dead_code)]
use chrono::{DateTime, NaiveDate, Utc};
use sqlx::PgPool;
use std::sync::atomic::{AtomicU64, Ordering};
use zoop_storage::{AnalysisVersions, NewRawFrame, NewSample, PostgresStore};

pub const DEVICE: &str = "TEST-RELIABILITY";
pub const VERSIONS: AnalysisVersions = AnalysisVersions {
    sleep: 2,
    workout: 2,
};
static NEXT: AtomicU64 = AtomicU64::new(0);
#[derive(Debug)]
pub struct Db {
    pub store: PostgresStore,
    pub pool: PgPool,
}
impl Db {
    pub async fn new() -> Self {
        // Explicitly invoked integration tests must fail, not silently pass, if the
        // test database is missing. Each test owns a fresh schema and migration set.
        let base = std::env::var("ZOOP_TEST_DATABASE_URL")
            .expect("set ZOOP_TEST_DATABASE_URL to a development database");
        let admin = PgPool::connect(&base).await.expect("test database");
        let schema = format!(
            "reliability_{}_{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        );
        sqlx::query(&format!("CREATE SCHEMA {schema}"))
            .execute(&admin)
            .await
            .unwrap();
        let url = format!(
            "{base}{}options=-csearch_path%3D{schema}",
            if base.contains('?') { '&' } else { '?' }
        );
        PostgresStore::migrate(&url).await.expect("migrations");
        let store = PostgresStore::connect(&url).await.unwrap();
        let pool = PgPool::connect(&url).await.unwrap();
        store.upsert_device(DEVICE, "TEST", None).await.unwrap();
        Self { store, pool }
    }
    pub async fn sql(&self, sql: &str) {
        sqlx::raw_sql(sql).execute(&self.pool).await.unwrap();
    }
    pub async fn count(&self, sql: &str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(&self.pool).await.unwrap()
    }
    pub async fn raw(&self, seq: i64) -> i64 {
        self.store
            .insert_raw_frame(&NewRawFrame {
                device_id: DEVICE,
                client_seq: seq,
                upload_id: None,
                channel: 5,
                received_at: Utc::now(),
                bytes: &[1, 2, 3],
            })
            .await
            .unwrap();
        sqlx::query_scalar("SELECT id FROM raw_frames WHERE client_seq=$1")
            .bind(seq)
            .fetch_one(&self.pool)
            .await
            .unwrap()
    }
}
pub fn at(s: &str) -> DateTime<Utc> {
    s.parse().unwrap()
}
pub fn day(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
pub fn sample(id: i64, ts: DateTime<Utc>) -> NewSample<'static> {
    NewSample {
        device_id: DEVICE,
        ts,
        hr: Some(100),
        rr_ms: vec![600],
        skin_temp_c: None,
        steps: Some(1),
        accel_dyn_g: None,
        gravity_g: None,
        activity: Some(1),
        band_state: 1,
        spo2_pct: None,
        raw_frame_id: id,
    }
}
