-- 1 Hz biometric summary decoded from R18 records.
CREATE TABLE samples (
    device_id     TEXT NOT NULL REFERENCES devices (id),
    ts            TIMESTAMPTZ NOT NULL,
    hr            SMALLINT,
    rr_ms         INTEGER[],
    skin_temp_c   REAL,
    steps         INTEGER,
    accel_dyn_g   REAL,
    activity      SMALLINT,
    quality       SMALLINT,
    raw_frame_id  BIGINT NOT NULL REFERENCES raw_frames (id),
    PRIMARY KEY (device_id, ts)
);

CREATE INDEX samples_ts_brin ON samples USING BRIN (ts);

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
