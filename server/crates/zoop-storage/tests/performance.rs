//! Projection equivalence and invalidation against the original raw-sample query.
#[path = "../../../tests/support/mod.rs"]
mod support;
use support::*;
use zoop_storage::DayRow;
async fn equivalent(db: &Db, zone: &str, limit: i64) {
    let expected: Vec<DayRow> = sqlx::query_as(include_str!("day_reference.sql"))
        .bind(DEVICE)
        .bind(zone)
        .bind(limit)
        .bind(10_i32)
        .bind(2_i32)
        .fetch_all(&db.pool)
        .await
        .unwrap();
    for _ in 0..2 {
        let actual = db.store.list_days(DEVICE, zone, limit, 2).await.unwrap();
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(&expected).unwrap()
        );
    }
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn cached_days_match_original_across_dst_gaps_nulls_and_late_replay() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    sqlx::query("INSERT INTO samples(device_id,ts,hr,steps,activity,skin_temp_c,band_state,raw_frame_id) SELECT $1,'2026-10-24T20:00:00Z'::timestamptz+n*interval '37 seconds',CASE WHEN n%11=0 THEN NULL ELSE (50+n%120)::smallint END,CASE WHEN n%17=0 THEN NULL ELSE n%100 END,(n%3)::smallint,(30+n%5)::real,(n%3)::smallint,$2 FROM generate_series(0,3500)n WHERE n%5<>0")
        .bind(DEVICE).bind(raw).execute(&db.pool).await.unwrap();
    for zone in ["UTC", "Europe/London", "Asia/Kathmandu", "America/New_York"] {
        for limit in [1, 7, 30, 365] {
            equivalent(&db, zone, limit).await;
        }
    }
    // Counter changes, new old samples and removal all invalidate cached days.
    db.sql("UPDATE samples SET steps=steps+2 WHERE ts>'2026-10-25T00:00:00Z' AND ts<'2026-10-25T00:10:00Z'").await;
    equivalent(&db, "Europe/London", 7).await;
    db.sql("DELETE FROM samples WHERE ts<'2026-10-25T00:00:00Z'")
        .await;
    equivalent(&db, "Europe/London", 7).await;
    let mut late = sample(raw, at("2026-09-01T00:00:00Z"));
    late.steps = Some(2);
    db.store.upsert_sample(&late).await.unwrap();
    equivalent(&db, "Europe/London", 365).await;
    late.steps = Some(3);
    db.store.upsert_sample(&late).await.unwrap();
    equivalent(&db, "Europe/London", 365).await;
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 1);
}
#[tokio::test]
#[ignore = "requires development Postgres"]
async fn concurrent_reads_and_ingest_do_not_lose_invalidation() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    let mut row = sample(raw, at("2026-10-25T12:00:00Z"));
    db.store.upsert_sample(&row).await.unwrap();
    let reads = async {
        for _ in 0..30 {
            db.store.list_days(DEVICE, "UTC", 7, 2).await.unwrap();
        }
    };
    let writes = async {
        for n in 0..30 {
            row.hr = Some(80 + n);
            db.store.upsert_sample(&row).await.unwrap();
        }
    };
    tokio::join!(reads, writes);
    equivalent(&db, "UTC", 7).await;
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn first_cache_fill_cannot_hide_a_concurrent_commit() {
    let db = Db::new().await;
    let raw = db.raw(1).await;
    let mut row = sample(raw, at("2026-10-25T12:00:00Z"));
    db.store.upsert_sample(&row).await.unwrap();
    let mut tx = db.pool.begin().await.unwrap();
    let _: Option<serde_json::Value> =
        sqlx::query_scalar("SELECT to_jsonb(refresh_day_summary($1,'UTC','2026-10-25'))")
            .bind(DEVICE)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    row.hr = Some(150);
    let writes = async {
        db.store.upsert_sample(&row).await.unwrap();
    };
    let commit = async {
        tokio::time::sleep(std::time::Duration::from_millis(40)).await;
        tx.commit().await.unwrap();
    };
    tokio::join!(writes, commit);
    equivalent(&db, "UTC", 7).await;
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn weight_cursor_upgrade_keeps_existing_readings_and_tombstones() {
    let db = Db::new().await;
    db.sql("DROP TRIGGER weight_cursor ON weight_readings; DROP FUNCTION advance_weight_cursor(); DROP TABLE weight_cursors; ALTER TABLE weight_readings DROP COLUMN change_seq;").await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name,removed) VALUES('TEST-RELIABILITY','health:old-a','2025-01-01',75,'health','Test',false),('TEST-RELIABILITY','health:old-b','2025-01-02',76,'health','Test',true)").await;
    db.sql(include_str!("../../../migrations/0011_weight_changes.sql"))
        .await;
    let page = db.store.weight_changes(DEVICE, 0, None, 250).await.unwrap();
    assert_eq!(page.rows.len(), 2);
    assert_eq!(page.watermark, 2);
    assert_eq!(page.rows.iter().filter(|r| r.removed).count(), 1);
}
