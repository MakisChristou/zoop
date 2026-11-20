-- Opt-in goal settings. Measurement ownership and Health export are unchanged.
CREATE TABLE weight_goals (
 device_id text PRIMARY KEY REFERENCES devices(id),
 revision bigint NOT NULL CHECK (revision > 0),
 active boolean NOT NULL,
 started_at timestamptz NOT NULL,
 pace_started_at timestamptz NOT NULL,
 timezone text NOT NULL,
 weekly_loss_kg double precision NOT NULL CHECK (weekly_loss_kg BETWEEN 0.1 AND 1.0),
 reminder_enabled boolean NOT NULL,
 reminder_weekday integer NOT NULL CHECK (reminder_weekday BETWEEN 1 AND 7),
 reminder_minute integer NOT NULL CHECK (reminder_minute BETWEEN 0 AND 1439),
 updated_at timestamptz NOT NULL
);
CREATE TABLE weight_goal_revisions (
 device_id text NOT NULL REFERENCES devices(id),
 revision bigint NOT NULL,
 settings jsonb NOT NULL,
 PRIMARY KEY(device_id, revision)
);
