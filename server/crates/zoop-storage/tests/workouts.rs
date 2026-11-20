//! Database-backed checks for the workout store. They run only when
//! `ZOOP_TEST_DATABASE_URL` points at a development database; `just ci` stays
//! database-free. Each test creates an isolated schema and applies the migrations.

use chrono::{DateTime, Duration, TimeZone, Utc};
use zoop_storage::{NewWorkout, PostgresStore};

const DEVICE: &str = "TEST-WORKOUT-STORE";
// One version per test so the two run in parallel without seeing each other's rows.
const ALGO_RESYNC: i32 = 999;
const ALGO_LABELS: i32 = 998;

#[path = "../../../tests/support/mod.rs"]
mod support;

async fn store() -> Option<PostgresStore> {
    std::env::var("ZOOP_TEST_DATABASE_URL").ok()?;
    let db = support::Db::new().await;
    db.store
        .upsert_device(DEVICE, "MG", None)
        .await
        .expect("device");
    Some(db.store)
}

fn workout<'a>(algo: i32, start: DateTime<Utc>, minutes: i64, kind: &'a str) -> NewWorkout<'a> {
    NewWorkout {
        device_id: DEVICE,
        algo_version: algo,
        start_ts: start,
        end_ts: start + Duration::minutes(minutes),
        kind,
        load: 3.0,
        avg_hr: 100.0,
        max_hr: 120,
        trimp: 25.0,
        zones_min: vec![10, 5, 0, 0, 0],
        kcal: Some(150.0),
        steps: 2500,
    }
}

async fn clean(store: &PostgresStore, algo: i32, from: DateTime<Utc>, to: DateTime<Utc>) {
    store.delete_labels(DEVICE, from, to).await.expect("labels");
    store
        .sync_workouts(DEVICE, algo, from, to, &[])
        .await
        .expect("clear");
}

#[tokio::test]
async fn resync_keeps_ids_updates_fields_and_drops_stale_sessions() {
    let Some(store) = store().await else { return };
    let day = Utc.with_ymd_and_hms(2031, 1, 5, 0, 0, 0).unwrap();
    let (from, to) = (day, day + Duration::days(1));
    clean(&store, ALGO_RESYNC, from, to).await;

    let walk = day + Duration::hours(8);
    let gym = day + Duration::hours(18);
    store
        .sync_workouts(
            DEVICE,
            ALGO_RESYNC,
            from,
            to,
            &[
                workout(ALGO_RESYNC, walk, 30, "walk"),
                workout(ALGO_RESYNC, gym, 45, "resistance"),
            ],
        )
        .await
        .expect("first sync");
    let first = store
        .list_workouts(DEVICE, ALGO_RESYNC, 10)
        .await
        .expect("list");
    assert_eq!(first.len(), 2);
    let gym_id = first.iter().find(|w| w.start_ts == gym).expect("gym").id;
    let walk_id = first.iter().find(|w| w.start_ts == walk).expect("walk").id;

    // Second pass: the gym session grew by ten minutes, the walk vanished, a new
    // evening walk appeared.
    let evening = day + Duration::hours(20);
    store
        .sync_workouts(
            DEVICE,
            ALGO_RESYNC,
            from,
            to,
            &[
                workout(ALGO_RESYNC, gym, 55, "resistance"),
                workout(ALGO_RESYNC, evening, 12, "walk"),
            ],
        )
        .await
        .expect("second sync");
    let second = store
        .list_workouts(DEVICE, ALGO_RESYNC, 10)
        .await
        .expect("list");
    assert_eq!(second.len(), 2);
    let gym_again = second.iter().find(|w| w.start_ts == gym).expect("gym kept");
    assert_eq!(
        gym_again.id, gym_id,
        "a re-run must not change a session's id"
    );
    assert_eq!(
        gym_again.duration_s,
        55 * 60,
        "fields are refreshed in place"
    );
    assert!(
        second.iter().all(|w| w.id != walk_id),
        "stale session removed"
    );
    assert!(
        second.iter().any(|w| w.start_ts == evening),
        "new session stored"
    );

    // A session outside the synced range is untouched by the sync.
    let next_day = to + Duration::hours(9);
    store
        .sync_workouts(
            DEVICE,
            ALGO_RESYNC,
            to,
            to + Duration::days(1),
            &[workout(ALGO_RESYNC, next_day, 20, "walk")],
        )
        .await
        .expect("next day");
    clean(&store, ALGO_RESYNC, from, to).await;
    let left = store
        .list_workouts(DEVICE, ALGO_RESYNC, 10)
        .await
        .expect("list");
    assert_eq!(left.len(), 1);
    assert_eq!(left[0].start_ts, next_day);
    clean(&store, ALGO_RESYNC, to, to + Duration::days(1)).await;
}

#[tokio::test]
async fn labels_apply_by_overlap_and_survive_resync() {
    let Some(store) = store().await else { return };
    let day = Utc.with_ymd_and_hms(2031, 2, 5, 0, 0, 0).unwrap();
    let (from, to) = (day, day + Duration::days(1));
    clean(&store, ALGO_LABELS, from, to).await;
    let start = day + Duration::hours(18);
    store
        .sync_workouts(
            DEVICE,
            ALGO_LABELS,
            from,
            to,
            &[workout(ALGO_LABELS, start, 45, "resistance")],
        )
        .await
        .expect("sync");
    let row = store
        .list_workouts(DEVICE, ALGO_LABELS, 10)
        .await
        .expect("list")
        .remove(0);
    assert_eq!(row.kind, "resistance");
    assert!(!row.edited);

    store
        .upsert_label(DEVICE, row.start_ts, row.end_ts, "activity")
        .await
        .expect("label");
    let labelled = store
        .get_workout(DEVICE, ALGO_LABELS, row.id)
        .await
        .expect("get")
        .expect("row");
    assert_eq!(labelled.kind, "activity");
    assert_eq!(labelled.detected_kind, "resistance");
    assert!(labelled.edited);

    // A recompute that shifts the session by a minute still carries the label.
    let shifted = start + Duration::minutes(1);
    store
        .sync_workouts(
            DEVICE,
            ALGO_LABELS,
            from,
            to,
            &[workout(ALGO_LABELS, shifted, 44, "resistance")],
        )
        .await
        .expect("resync");
    let after = store
        .list_workouts(DEVICE, ALGO_LABELS, 10)
        .await
        .expect("list")
        .remove(0);
    assert_eq!(after.start_ts, shifted);
    assert_eq!(
        after.kind, "activity",
        "label follows the session by overlap"
    );

    // A label covering less than half the session does not apply.
    let far = day + Duration::hours(6);
    store
        .sync_workouts(
            DEVICE,
            ALGO_LABELS,
            from,
            to,
            &[workout(ALGO_LABELS, far, 60, "walk")],
        )
        .await
        .expect("resync 2");
    store
        .upsert_label(DEVICE, far, far + Duration::minutes(10), "activity")
        .await
        .expect("short label");
    let short = store
        .list_workouts(DEVICE, ALGO_LABELS, 10)
        .await
        .expect("list")
        .remove(0);
    assert_eq!(short.kind, "walk");
    clean(&store, ALGO_LABELS, from, to).await;
}
