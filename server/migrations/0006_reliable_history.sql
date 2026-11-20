-- The legacy namespace remains available for queued frames from older app builds.
-- Raw payloads and existing upload identities are never rewritten.
ALTER TABLE raw_frames ADD COLUMN upload_id TEXT;
CREATE UNIQUE INDEX raw_frames_upload_identity ON raw_frames(device_id, upload_id) WHERE upload_id IS NOT NULL;
CREATE UNIQUE INDEX raw_frames_legacy_identity ON raw_frames(device_id, client_seq) WHERE upload_id IS NULL;
ALTER TABLE raw_frames DROP CONSTRAINT raw_frames_device_id_client_seq_key;
ALTER TABLE raw_frames ADD COLUMN decode_error TEXT;
ALTER TABLE raw_frames ADD COLUMN decode_status TEXT;
CREATE INDEX raw_frames_decode_revision ON raw_frames(decoded_proto,id);

-- These are derived rows. Repair previous replay duplicates before enforcing identity.
DELETE FROM events a USING events b WHERE a.raw_frame_id=b.raw_frame_id AND a.id>b.id;
DELETE FROM ecg_strips a USING ecg_strips b WHERE a.raw_frame_id=b.raw_frame_id AND a.id>b.id;
CREATE UNIQUE INDEX events_raw_identity ON events(raw_frame_id);
CREATE UNIQUE INDEX ecg_raw_identity ON ecg_strips(raw_frame_id);

CREATE SEQUENCE analysis_claim_ids;
CREATE TABLE analysis_jobs (
 device_id TEXT NOT NULL REFERENCES devices(id),
 kind TEXT NOT NULL CHECK(kind IN ('sleep','workout')),
 day DATE NOT NULL,
 tz TEXT NOT NULL,
 algo_version INTEGER NOT NULL,
 generation BIGINT NOT NULL DEFAULT 1,
 completed_generation BIGINT NOT NULL DEFAULT 0,
 claim_id BIGINT,
 claimed_generation BIGINT,
 lease_until TIMESTAMPTZ,
 available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 attempts INTEGER NOT NULL DEFAULT 0,
 last_error TEXT,
 completed_at TIMESTAMPTZ,
 inputs JSONB,
 backfill BOOLEAN NOT NULL DEFAULT true,
 PRIMARY KEY(device_id,kind,day,tz,algo_version)
);
CREATE INDEX analysis_pending ON analysis_jobs(available_at,day) WHERE generation>completed_generation;
CREATE TABLE analysis_bootstraps (
 device_id TEXT NOT NULL REFERENCES devices(id), tz TEXT NOT NULL,
 sleep_version INTEGER NOT NULL, workout_version INTEGER NOT NULL,
 completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(device_id,tz,sleep_version,workout_version)
);
CREATE TABLE worker_status (
 name TEXT PRIMARY KEY, heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 last_success TIMESTAMPTZ, last_error TEXT, paused BOOLEAN NOT NULL DEFAULT false
);
ALTER TABLE workouts ADD COLUMN notification_eligible BOOLEAN NOT NULL DEFAULT false;
CREATE TABLE profile_revisions (
 id BIGSERIAL PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id),
 effective_at TIMESTAMPTZ NOT NULL, profile JSONB NOT NULL
);
-- Historic profile values were not recorded; the first snapshot is an explicit assumption.
INSERT INTO profile_revisions(device_id,effective_at,profile)
 SELECT device_id,'-infinity'::timestamptz,to_jsonb(p) FROM profiles p;
CREATE INDEX profile_revision_lookup ON profile_revisions(device_id,effective_at DESC,id DESC);

CREATE INDEX IF NOT EXISTS samples_raw_frame_idx ON samples(raw_frame_id);

-- Completed empty nights also supersede older versions. Downstream calculations
-- must not resurrect an obsolete window or resting heart rate.
CREATE VIEW effective_sleeps AS
 SELECT s.* FROM sleeps s WHERE NOT EXISTS (
   SELECT 1 FROM sleeps newer WHERE newer.device_id=s.device_id AND newer.night_of=s.night_of AND newer.algo_version>s.algo_version
 ) AND NOT EXISTS (
   SELECT 1 FROM analysis_jobs j WHERE j.device_id=s.device_id AND j.kind='sleep'
     AND j.day=s.night_of AND j.completed_generation>0 AND j.algo_version>s.algo_version
 );
