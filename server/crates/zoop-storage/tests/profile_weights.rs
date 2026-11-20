//! Profile weight must follow measurements without leaking future values into history.
#[path = "../../../tests/support/mod.rs"]
mod support;
use support::{DEVICE, Db, at};
use zoop_storage::NewProfile;

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn measured_weight_is_health_first_dated_and_reversible() {
    let db = Db::new().await;
    let fallback = NewProfile {
        device_id: DEVICE,
        sex: Some("male"),
        birth_year: Some(1980),
        weight_kg: Some(80.0),
        height_cm: Some(180.0),
        tz: "Europe/Athens",
    };
    db.store.upsert_profile(&fallback).await.unwrap();
    db.sql(
        "INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES
      ('TEST-RELIABILITY','health:new','2025-06-01T07:00:00Z',72,'health','Test scale'),
      ('TEST-RELIABILITY','zoop:same-day','2025-06-01T14:00:00Z',90,'snoop','Zoop'),
      ('TEST-RELIABILITY','health:old-import','2025-01-01T07:00:00Z',75,'health','Test scale')",
    )
    .await;
    let current = db.store.get_profile(DEVICE).await.unwrap().unwrap();
    assert_eq!(current.weight_kg, Some(72.0));
    assert_eq!(current.weight_source.as_deref(), Some("health"));
    assert_eq!(current.weight_measured_at, Some(at("2025-06-01T07:00:00Z")));
    assert_eq!(
        db.store
            .profile_at(DEVICE, at("2025-05-01T00:00:00Z"))
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(75.0)
    );
    assert_eq!(
        db.store
            .profile_at(DEVICE, at("2024-01-01T00:00:00Z"))
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(80.0)
    );
    db.store
        .upsert_profile(&NewProfile {
            weight_kg: Some(99.0),
            height_cm: Some(181.0),
            ..fallback
        })
        .await
        .unwrap();
    let updated = db.store.get_profile(DEVICE).await.unwrap().unwrap();
    assert_eq!(updated.weight_kg, Some(72.0));
    assert_eq!(updated.height_cm, Some(181.0));
    db.sql("UPDATE weight_readings SET removed=true WHERE id='health:new'")
        .await;
    assert_eq!(
        db.store
            .get_profile(DEVICE)
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(90.0)
    );
    db.sql("UPDATE weight_readings SET removed=true").await;
    assert_eq!(
        db.store
            .get_profile(DEVICE)
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(80.0)
    );
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','health:future',now()+interval '1 day',100,'health','Test scale')").await;
    assert_eq!(
        db.store
            .get_profile(DEVICE)
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(80.0)
    );
    assert!(db.store.get_profile("OTHER").await.unwrap().is_none());
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn weight_changes_requeue_only_affected_workout_days() {
    let db = Db::new().await;
    db.sql("INSERT INTO analysis_jobs(device_id,kind,day,tz,algo_version,generation,completed_generation)
      VALUES('TEST-RELIABILITY','workout','2025-01-01','UTC',4,1,1),
            ('TEST-RELIABILITY','workout','2025-01-02','UTC',4,1,1),
            ('TEST-RELIABILITY','sleep','2025-01-02','UTC',4,1,1)").await;
    db.sql("INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name) VALUES('TEST-RELIABILITY','health:test','2025-01-02T07:00:00Z',75,'health','Test scale')").await;
    assert_eq!(db.count("SELECT count(*) FROM analysis_jobs WHERE generation>completed_generation AND kind='workout' AND day='2025-01-02'").await,1);
    assert_eq!(
        db.count("SELECT count(*) FROM analysis_jobs WHERE generation>completed_generation")
            .await,
        1
    );
    db.sql("UPDATE weight_readings SET source_name='Renamed scale'")
        .await;
    assert_eq!(
        db.count("SELECT max(generation) FROM analysis_jobs").await,
        2
    );
    db.sql("UPDATE weight_readings SET removed=true").await;
    assert_eq!(
        db.count("SELECT max(generation) FROM analysis_jobs").await,
        3
    );
}
