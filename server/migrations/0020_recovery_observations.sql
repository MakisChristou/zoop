-- Recovery is independently versioned. Append observations; never overwrite the
-- earlier score when corrected sleep or late data changes its source snapshot.
CREATE TABLE recovery_observations (
    id bigserial PRIMARY KEY,
    device_id text NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    day date NOT NULL,
    tz text NOT NULL,
    formula_version integer NOT NULL,
    input_fingerprint text NOT NULL,
    inputs jsonb NOT NULL,
    result jsonb NOT NULL,
    observed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(device_id,day,tz,formula_version,input_fingerprint)
);
CREATE INDEX recovery_observations_day ON recovery_observations(device_id,day,observed_at DESC);
-- Completed rows also serve as the bootstrap marker. Generations prevent a
-- concurrent sleep publication being lost when an older observation finishes.
CREATE TABLE recovery_jobs (
    device_id text NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    day date NOT NULL,
    tz text NOT NULL,
    formula_version integer NOT NULL,
    generation bigint NOT NULL DEFAULT 1,
    completed_generation bigint NOT NULL DEFAULT 0,
    available_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(device_id,day,tz,formula_version)
);
CREATE INDEX recovery_jobs_pending ON recovery_jobs(available_at,day)
    WHERE generation>completed_generation;
