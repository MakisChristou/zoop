-- Derived coverage evidence only. Raw recordings and score history are unchanged.
CREATE TABLE sleep_evidence (
    session_id bigint PRIMARY KEY REFERENCES sleep_sessions(id) ON DELETE CASCADE,
    revision bigint NOT NULL,
    boundary_complete boolean NOT NULL,
    hr_samples bigint NOT NULL,
    measured_at timestamptz NOT NULL DEFAULT now()
);
-- Revisit observations once to warm evidence without redetecting historical sleep.
UPDATE recovery_jobs SET generation=generation+1,available_at=now();
CREATE INDEX recovery_observations_inputs
    ON recovery_observations(device_id,tz,formula_version,input_fingerprint);
