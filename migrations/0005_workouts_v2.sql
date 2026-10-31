-- Workouts v2: per-session zones, training impulse, load, calories and steps, plus a
-- natural key so re-running a day replaces its sessions. User labels and the body
-- profile are unversioned inputs the analytics read, so a recompute at a new
-- algo_version keeps them.
ALTER TABLE workouts
    ADD COLUMN load      REAL,
    ADD COLUMN trimp     REAL,
    ADD COLUMN zones_min INTEGER[],
    ADD COLUMN kcal      REAL,
    ADD COLUMN steps     INTEGER,
    ADD CONSTRAINT workouts_natural_key UNIQUE (device_id, algo_version, start_ts);

ALTER TABLE strains
    RENAME COLUMN day_strain TO load;
ALTER TABLE strains
    ADD COLUMN kcal REAL;

-- A user's correction of a detected session's kind. Matched to sessions by time
-- overlap, so it survives a recompute that shifts the boundaries by a minute.
CREATE TABLE workout_labels (
    device_id  TEXT NOT NULL REFERENCES devices (id),
    start_ts   TIMESTAMPTZ NOT NULL,
    end_ts     TIMESTAMPTZ NOT NULL,
    kind       TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, start_ts)
);

-- Body profile for the calorie and zone equations, and the home time zone that
-- days are cut in.
CREATE TABLE profiles (
    device_id  TEXT PRIMARY KEY REFERENCES devices (id),
    sex        TEXT,
    birth_year SMALLINT,
    weight_kg  REAL,
    height_cm  REAL,
    tz         TEXT NOT NULL DEFAULT 'UTC',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
