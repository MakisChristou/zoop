//! Run explicitly with --ignored and a development SNOOP_TEST_DATABASE_URL.
#[path = "../../../tests/support/mod.rs"]
mod support;
use chrono::{Duration, Utc};
use serde_json::json;
use snoop_storage::{
    DecodeOutput, DecodedFrame, IngestOutcome, NewEcgStrip, NewEvent, NewProfile, NewRawFrame,
    NewSleep, NewStrain, NewWorkout,
};
use support::*;

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn receipts_verify_content_and_keep_legacy_and_reinstall_namespaces_separate() {
    let db = Db::new().await;
    let mut frame = NewRawFrame {
        device_id: DEVICE,
        client_seq: 1,
        upload_id: None,
        channel: 5,
        received_at: Utc::now(),
        bytes: &[1, 2],
    };
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Stored
    );
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Duplicate
    );
    frame.bytes = &[8, 9];
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Conflict
    );
    frame.upload_id = Some("00000000-0000-4000-8000-000000000001");
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Stored
    );
    frame.client_seq = 999; // UUID identity does not depend on a phone counter.
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Duplicate
    );
    frame.channel = 4;
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Conflict
    );
    frame.upload_id = Some("00000000-0000-4000-8000-000000000002");
    frame.client_seq = 1;
    assert_eq!(
        db.store.insert_raw_frame(&frame).await.unwrap(),
        IngestOutcome::Stored
    );
    assert_eq!(db.count("SELECT count(*) FROM raw_frames").await, 3);
    let bytes: Vec<u8> = sqlx::query_scalar("SELECT bytes FROM raw_frames WHERE upload_id IS NULL")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    assert_eq!(bytes, [1, 2]);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn decode_replay_is_idempotent_and_outputs_marker_and_jobs_rollback_together() {
    let db = Db::new().await;
    let first = db.raw(1).await;
    let second = db.raw(2).await;
    let third = db.raw(3).await;
    let ts = at("2025-01-01T20:00:00Z");
    let frames = vec![
        DecodedFrame {
            frame_id: first,
            device_id: DEVICE,
            output: DecodeOutput::Sample(sample(first, ts)),
        },
        DecodedFrame {
            frame_id: second,
            device_id: DEVICE,
            output: DecodeOutput::Event(NewEvent {
                device_id: DEVICE,
                ts,
                event_code: 4,
                payload: vec![7],
                raw_frame_id: second,
            }),
        },
        DecodedFrame {
            frame_id: third,
            device_id: DEVICE,
            output: DecodeOutput::Ecg(NewEcgStrip {
                device_id: DEVICE,
                ts,
                layout: 1,
                quality: None,
                samples: vec![100, 101],
                raw_frame_id: third,
            }),
        },
    ];
    db.sql("ALTER TABLE analysis_jobs ADD CONSTRAINT injected_failure CHECK (false)")
        .await;
    assert!(db.store.save_decoded(&frames, 3, VERSIONS).await.is_err());
    assert_eq!(db.count("SELECT count(*) FROM samples").await, 0);
    assert_eq!(db.count("SELECT count(*) FROM events").await, 0);
    assert_eq!(db.count("SELECT count(*) FROM ecg_strips").await, 0);
    assert_eq!(
        db.count("SELECT count(*) FROM raw_frames WHERE decoded_proto IS NOT NULL")
            .await,
        0
    );
    db.sql("ALTER TABLE analysis_jobs DROP CONSTRAINT injected_failure")
        .await;
    db.store.save_decoded(&frames, 3, VERSIONS).await.unwrap();
    db.store.save_decoded(&frames, 3, VERSIONS).await.unwrap();
    db.store.save_decoded(&frames, 4, VERSIONS).await.unwrap();
    assert_eq!(db.count("SELECT count(*) FROM samples").await, 1);
    assert_eq!(db.count("SELECT count(*) FROM events").await, 1);
    assert_eq!(db.count("SELECT count(*) FROM ecg_strips").await, 1);
    assert_eq!(
        db.count("SELECT count(*) FROM analysis_jobs WHERE day<'2025-01-10'")
            .await,
        4
    );
    assert_eq!(
        db.count("SELECT count(*) FROM raw_frames WHERE decoded_proto=4")
            .await,
        3
    );
    let bad = db.raw(4).await;
    db.store
        .save_decoded(
            &[DecodedFrame {
                frame_id: bad,
                device_id: DEVICE,
                output: DecodeOutput::Failed("bad semantic payload".into()),
            }],
            4,
            VERSIONS,
        )
        .await
        .unwrap();
    let status = db
        .store
        .processing_status(DEVICE, 4, VERSIONS)
        .await
        .unwrap();
    assert_eq!(status.decode_failures, 1);
    assert_eq!(status.pending_decode, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn claims_dependencies_generation_fences_leases_retries_and_atomic_publication() {
    let db = Db::new().await;
    let d = day("2025-01-02");
    let from = at("2025-01-02T00:00:00Z");
    let to = from + Duration::days(1);
    db.store
        .request_analysis(DEVICE, "workout", d, "UTC", 2, true)
        .await
        .unwrap();
    db.store
        .request_analysis(DEVICE, "sleep", d, "UTC", 2, true)
        .await
        .unwrap();
    let sleep = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    assert_eq!(sleep.kind, "sleep");
    assert!(
        db.store.claim_analysis(VERSIONS).await.unwrap().is_none(),
        "day waits for sleep, even when another worker has claimed it"
    );
    assert!(
        db.store
            .publish_night(&sleep, None, json!({}))
            .await
            .unwrap()
    );
    let first = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    assert!(
        db.store.claim_analysis(VERSIONS).await.unwrap().is_none(),
        "claim excludes another worker"
    );
    db.store
        .request_analysis(DEVICE, "workout", d, "UTC", 2, false)
        .await
        .unwrap();
    assert!(
        !db.store
            .publish_day(&first, from, to, &[], None, json!({}))
            .await
            .unwrap(),
        "new input fences stale calculation"
    );
    let old = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    db.sql("UPDATE analysis_jobs SET lease_until=now()-interval '1 second' WHERE kind='workout'")
        .await;
    let current = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    assert_ne!(old.claim_id, current.claim_id);
    assert!(
        !db.store
            .publish_day(&old, from, to, &[], None, json!({}))
            .await
            .unwrap(),
        "expired worker cannot overwrite replacement"
    );
    db.store
        .fail_analysis(&current, "injected outage")
        .await
        .unwrap();
    assert!(
        db.store.claim_analysis(VERSIONS).await.unwrap().is_none(),
        "failed attempt backs off"
    );
    db.sql("UPDATE analysis_jobs SET available_at=now() WHERE kind='workout'")
        .await;
    let retry = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    let workout = NewWorkout {
        device_id: DEVICE,
        algo_version: 2,
        start_ts: from + Duration::hours(8),
        end_ts: from + Duration::hours(9),
        kind: "walk",
        load: 5.0,
        avg_hr: 110.0,
        max_hr: 130,
        trimp: 30.0,
        zones_min: vec![20, 10, 0, 0, 0],
        kcal: Some(200.0),
        steps: 3000,
    };
    let strain = NewStrain {
        device_id: DEVICE,
        day: d,
        algo_version: 2,
        load: 5.0,
        trimp: 30.0,
        zones_min: vec![20, 10, 0, 0, 0],
        kcal: Some(200.0),
    };
    db.sql("ALTER TABLE strains ADD CONSTRAINT injected_failure CHECK(false)")
        .await;
    assert!(
        db.store
            .publish_day(
                &retry,
                from,
                to,
                std::slice::from_ref(&workout),
                Some(&strain),
                json!({})
            )
            .await
            .is_err()
    );
    assert_eq!(db.count("SELECT count(*) FROM workouts").await, 0);
    assert_eq!(
        db.count(
            "SELECT count(*) FROM analysis_jobs WHERE kind='workout' AND completed_generation>0"
        )
        .await,
        0
    );
    db.sql("ALTER TABLE strains DROP CONSTRAINT injected_failure")
        .await;
    assert!(
        db.store
            .publish_day(
                &retry,
                from,
                to,
                &[workout],
                Some(&strain),
                json!({"profile":"snapshot"})
            )
            .await
            .unwrap()
    );
    assert_eq!(db.count("SELECT count(*) FROM strains").await, 1);
    assert_eq!(
        db.count("SELECT count(*) FROM workouts WHERE NOT notification_eligible")
            .await,
        1
    );
    let status = db
        .store
        .processing_status(DEVICE, 3, VERSIONS)
        .await
        .unwrap();
    assert_eq!(status.pending_analysis, 0);
    assert_eq!(status.failed_analysis, 0);
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn bootstrap_is_once_per_version_and_empty_results_replace_old_versions() {
    let db = Db::new().await;
    let ts = at("2025-01-02T10:00:00Z");
    let d = ts.date_naive();
    let id = db.raw(1).await;
    db.store.upsert_sample(&sample(id, ts)).await.unwrap();
    db.store.seed_history(VERSIONS).await.unwrap();
    db.store.seed_history(VERSIONS).await.unwrap();
    assert_eq!(db.count("SELECT count(*) FROM analysis_jobs").await, 2);
    assert_eq!(
        db.count("SELECT max(generation) FROM analysis_jobs").await,
        1
    );
    let w = NewWorkout {
        device_id: DEVICE,
        algo_version: 1,
        start_ts: ts,
        end_ts: ts + Duration::minutes(30),
        kind: "walk",
        load: 4.0,
        avg_hr: 100.0,
        max_hr: 120,
        trimp: 20.0,
        zones_min: vec![30, 0, 0, 0, 0],
        kcal: None,
        steps: 2000,
    };
    db.store
        .sync_workouts(DEVICE, 1, ts, ts + Duration::hours(1), &[w])
        .await
        .unwrap();
    assert_eq!(
        db.store.list_workouts(DEVICE, 2, 10).await.unwrap().len(),
        1,
        "old version readable during backfill"
    );
    let job = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    db.store.publish_night(&job, None, json!({})).await.unwrap();
    let job = db.store.claim_analysis(VERSIONS).await.unwrap().unwrap();
    db.store
        .publish_day(
            &job,
            at("2025-01-02T00:00:00Z"),
            at("2025-01-03T00:00:00Z"),
            &[],
            None,
            json!({}),
        )
        .await
        .unwrap();
    assert!(
        db.store
            .list_workouts(DEVICE, 2, 10)
            .await
            .unwrap()
            .is_empty(),
        "completed empty result hides old sessions"
    );
    assert_eq!(
        db.count("SELECT count(*) FROM workouts WHERE algo_version=1")
            .await,
        1,
        "old results remain stored"
    );
    db.store
        .request_analysis(DEVICE, "workout", d, "UTC", 2, false)
        .await
        .unwrap();
    assert!(
        !db.store
            .claim_analysis(VERSIONS)
            .await
            .unwrap()
            .unwrap()
            .backfill,
        "later live updates no longer inherit bootstrap suppression"
    );
}

#[tokio::test]
#[ignore = "requires development Postgres"]
async fn as_of_inputs_profiles_and_time_zone_boundaries() {
    let db = Db::new().await;
    let p = NewProfile {
        device_id: DEVICE,
        sex: Some("male"),
        birth_year: Some(1985),
        weight_kg: Some(80.0),
        height_cm: None,
        tz: "Asia/Kathmandu",
    };
    db.store.upsert_profile(&p).await.unwrap();
    let before = db
        .store
        .profile_at(DEVICE, at("2025-01-01T00:00:00Z"))
        .await
        .unwrap()
        .unwrap();
    let changed = NewProfile {
        weight_kg: Some(85.0),
        ..p
    };
    db.store.upsert_profile(&changed).await.unwrap();
    assert_eq!(
        db.store
            .profile_at(DEVICE, at("2025-01-01T00:00:00Z"))
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        before.weight_kg
    );
    assert_eq!(
        db.store
            .profile_at(DEVICE, Utc::now() + Duration::hours(1))
            .await
            .unwrap()
            .unwrap()
            .weight_kg,
        Some(85.0)
    );
    let a = db.raw(1).await;
    let b = db.raw(2).await;
    let samples = [
        DecodedFrame {
            frame_id: a,
            device_id: DEVICE,
            output: DecodeOutput::Sample(sample(a, at("2025-01-01T18:10:00Z"))),
        },
        DecodedFrame {
            frame_id: b,
            device_id: DEVICE,
            output: DecodeOutput::Sample(sample(b, at("2025-01-01T18:20:00Z"))),
        },
    ];
    db.store.save_decoded(&samples, 3, VERSIONS).await.unwrap();
    assert_eq!(
        db.count("SELECT count(*) FROM analysis_jobs WHERE kind='workout'")
            .await,
        4,
        "both local dates cross inside one UTC hour"
    );
    let (start, end) = db
        .store
        .local_day_bounds(day("2026-10-25"), "Europe/London")
        .await
        .unwrap();
    assert_eq!((end - start).num_hours(), 25);
    let future = db.raw(3).await;
    let mut high = sample(future, at("2025-02-01T12:00:00Z"));
    high.hr = Some(220);
    db.store.upsert_sample(&high).await.unwrap();
    assert_eq!(
        db.store
            .observed_hr_max_at(DEVICE, 90, at("2025-01-02T00:00:00Z"))
            .await
            .unwrap(),
        Some(100.0)
    );
    let night = NewSleep {
        device_id: DEVICE,
        night_of: day("2025-01-01"),
        algo_version: 1,
        start_ts: at("2024-12-31T22:00:00Z"),
        end_ts: at("2025-01-01T06:00:00Z"),
        stages: json!([]),
        metrics: json!({"physiology":{"resting_hr":55.0}}),
    };
    db.store.upsert_sleep(&night).await.unwrap();
    assert_eq!(
        db.store
            .resting_hr_at(DEVICE, at("2025-01-02T00:00:00Z"))
            .await
            .unwrap(),
        Some(55.0)
    );
    db.store
        .request_analysis(DEVICE, "sleep", day("2025-01-01"), "UTC", 2, true)
        .await
        .unwrap();
    db.sql("UPDATE analysis_jobs SET completed_generation=generation WHERE kind='sleep' AND day='2025-01-01'").await;
    assert_eq!(
        db.store
            .resting_hr_at(DEVICE, at("2025-01-02T00:00:00Z"))
            .await
            .unwrap(),
        None,
        "empty newer night cannot resurrect an old resting HR"
    );
}
