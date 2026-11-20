-- 1 Hz biometric summary decoded from R18 records.
CREATE TABLE samples (
    device_id     TEXT NOT NULL REFERENCES devices (id),
    ts            TIMESTAMPTZ NOT NULL,
    hr            SMALLINT,
    rr_ms         INTEGER[],
    skin_temp_c   REAL,
    steps         INTEGER,
    accel_dyn_g   REAL,
    activity      SMALLINT,                      -- 0 still, 1 walk, 2 run; NULL = other
    band_state    SMALLINT NOT NULL,             -- strap's own flag: 0 wake, 1 still, 2 sleep, 3 up
    spo2_pct      SMALLINT,                      -- valid only inside the strap's SpO2 windows
    raw_frame_id  BIGINT NOT NULL REFERENCES raw_frames (id),
    PRIMARY KEY (device_id, ts)
);

CREATE INDEX samples_ts_brin ON samples USING BRIN (ts);
CREATE INDEX samples_sleep_idx ON samples (device_id, ts) WHERE band_state = 2;

-- Strap events: wear on/off, charge, double tap, sleep envelope markers.
CREATE TABLE events (
    id            BIGSERIAL PRIMARY KEY,
    device_id     TEXT NOT NULL REFERENCES devices (id),
    ts            TIMESTAMPTZ NOT NULL,
    event_code    SMALLINT NOT NULL,
    payload       BYTEA,
    raw_frame_id  BIGINT NOT NULL REFERENCES raw_frames (id)
);

CREATE INDEX events_device_ts_idx ON events (device_id, ts);

-- WHOOP MG ECG strips (R16 / R17).
CREATE TABLE ecg_strips (
    id            BIGSERIAL PRIMARY KEY,
    device_id     TEXT NOT NULL REFERENCES devices (id),
    ts            TIMESTAMPTZ NOT NULL,
    layout        SMALLINT NOT NULL,
    quality       SMALLINT,
    samples       INTEGER[] NOT NULL,
    raw_frame_id  BIGINT NOT NULL REFERENCES raw_frames (id)
);

CREATE INDEX ecg_strips_device_ts_idx ON ecg_strips (device_id, ts);
