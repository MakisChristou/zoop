-- Daily derived objects. One row per (device, day, algo_version) so a method change
-- backfills next to the old numbers instead of overwriting them.
CREATE TABLE sleeps (
    device_id     TEXT NOT NULL REFERENCES devices (id),
    night_of      DATE NOT NULL,
    algo_version  INTEGER NOT NULL,
    start_ts      TIMESTAMPTZ NOT NULL,
    end_ts        TIMESTAMPTZ NOT NULL,
    stages        JSONB NOT NULL,
    metrics       JSONB NOT NULL,
    PRIMARY KEY (device_id, night_of, algo_version)
);

CREATE TABLE recoveries (
    device_id     TEXT NOT NULL REFERENCES devices (id),
    day           DATE NOT NULL,
    algo_version  INTEGER NOT NULL,
    score         REAL,
    hrv_rmssd_ms  REAL,
    rhr_bpm       REAL,
    resp_rate     REAL,
    skin_temp_c   REAL,
    spo2_pct      REAL,
    inputs        JSONB NOT NULL,
    PRIMARY KEY (device_id, day, algo_version)
);

CREATE TABLE strains (
    device_id     TEXT NOT NULL REFERENCES devices (id),
    day           DATE NOT NULL,
    algo_version  INTEGER NOT NULL,
    day_strain    REAL,
    trimp         REAL,
    zones_min     INTEGER[],
    PRIMARY KEY (device_id, day, algo_version)
);

CREATE TABLE workouts (
    id             BIGSERIAL PRIMARY KEY,
    device_id      TEXT NOT NULL REFERENCES devices (id),
    algo_version   INTEGER NOT NULL,
    start_ts       TIMESTAMPTZ NOT NULL,
    end_ts         TIMESTAMPTZ NOT NULL,
    kind           TEXT,
    strain         REAL,
    avg_hr         REAL,
    max_hr         SMALLINT,
    auto_detected  BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE journal (
    device_id  TEXT NOT NULL REFERENCES devices (id),
    day        DATE NOT NULL,
    entries    JSONB NOT NULL,
    PRIMARY KEY (device_id, day)
);
