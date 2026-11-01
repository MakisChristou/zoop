-- Detector candidates remain versioned in workouts. This is the stable, editable
-- user-facing record. A shared sequence preserves legacy numeric notification links.
CREATE TABLE workout_sessions (
 id BIGINT PRIMARY KEY DEFAULT nextval('workouts_id_seq'),
 device_id TEXT NOT NULL REFERENCES devices(id),
 start_ts TIMESTAMPTZ NOT NULL, end_ts TIMESTAMPTZ NOT NULL,
 duration_s BIGINT GENERATED ALWAYS AS (extract(epoch FROM end_ts-start_ts)::bigint) STORED,
 kind TEXT NOT NULL CHECK(kind IN ('walk','resistance','activity')),
 detected_kind TEXT NOT NULL,
 edited BOOLEAN NOT NULL DEFAULT false,
 fixed BOOLEAN NOT NULL DEFAULT false,
 auto_detected BOOLEAN NOT NULL DEFAULT true,
 notification_eligible BOOLEAN NOT NULL DEFAULT false,
 revision BIGINT NOT NULL DEFAULT 1,
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','removed','superseded')),
 last_edit TEXT,
 replacements BIGINT[] NOT NULL DEFAULT '{}',
 metrics JSONB NOT NULL DEFAULT '{}',
 metrics_pending BOOLEAN NOT NULL DEFAULT false,
 timezone TEXT NOT NULL DEFAULT 'UTC',
 CHECK(end_ts > start_ts)
);
CREATE INDEX workout_session_dates ON workout_sessions(device_id,start_ts,end_ts);
CREATE TABLE workout_corrections (
 operation_id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id),
 request JSONB NOT NULL, before_state JSONB NOT NULL, affected_ids BIGINT[] NOT NULL,
 scope_start TIMESTAMPTZ, scope_end TIMESTAMPTZ,
 active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK((scope_start IS NULL AND scope_end IS NULL) OR scope_end>scope_start)
);
CREATE INDEX workout_correction_scopes ON workout_corrections(device_id,scope_start,scope_end) WHERE active;
CREATE TABLE workout_aliases (
 legacy_id BIGINT PRIMARY KEY, session_id BIGINT NOT NULL REFERENCES workout_sessions(id)
);

INSERT INTO workout_sessions(id,device_id,start_ts,end_ts,kind,detected_kind,edited,fixed,
 auto_detected,notification_eligible,timezone,metrics)
SELECT w.id,w.device_id,w.start_ts,w.end_ts,coalesce(l.kind,w.kind,'activity'),
 coalesce(w.kind,'activity'),l.kind IS NOT NULL,l.kind IS NOT NULL,w.auto_detected,false,
 coalesce(p.tz,'UTC'),jsonb_build_object('load',w.load,'avg_hr',w.avg_hr,'max_hr',w.max_hr,
 'trimp',w.trimp,'zones_min',w.zones_min,'kcal',w.kcal,'steps',w.steps)
FROM workouts w LEFT JOIN profiles p ON p.device_id=w.device_id
LEFT JOIN LATERAL (
 SELECT kind FROM workout_labels l WHERE l.device_id=w.device_id
 AND l.end_ts>w.start_ts AND l.start_ts<w.end_ts
 AND extract(epoch FROM least(l.end_ts,w.end_ts)-greatest(l.start_ts,w.start_ts))*2
 >=extract(epoch FROM w.end_ts-w.start_ts) ORDER BY updated_at DESC LIMIT 1
) l ON true
WHERE w.algo_version=coalesce(
 (SELECT max(j.algo_version) FROM analysis_jobs j WHERE j.device_id=w.device_id
 AND j.kind='workout' AND j.completed_generation>0 AND j.tz=coalesce(p.tz,'UTC')
 AND j.day=(w.start_ts AT TIME ZONE coalesce(p.tz,'UTC'))::date),
 (SELECT max(v.algo_version) FROM workouts v WHERE v.device_id=w.device_id
 AND (v.start_ts AT TIME ZONE coalesce(p.tz,'UTC'))::date=(w.start_ts AT TIME ZONE coalesce(p.tz,'UTC'))::date));

INSERT INTO workout_aliases(legacy_id,session_id)
SELECT w.id,s.id FROM workouts w JOIN LATERAL (
 SELECT id FROM workout_sessions s WHERE s.device_id=w.device_id
 AND s.start_ts<w.end_ts AND s.end_ts>w.start_ts
 ORDER BY least(s.end_ts,w.end_ts)-greatest(s.start_ts,w.start_ts) DESC,s.id LIMIT 1
) s ON true;

-- A previously labelled workout is confirmed user intent too. Preserve its current
-- bounds, give it the same ownership/undo semantics, and retain the old label table.
INSERT INTO workout_corrections(operation_id,device_id,request,before_state,affected_ids,scope_start,scope_end)
SELECT 'legacy-label-'||id,device_id,jsonb_build_object('action','migrated_label'),
 jsonb_build_array((to_jsonb(s)-'metrics')||s.metrics||jsonb_build_object('edited',false,'fixed',false,'kind',detected_kind)),
 ARRAY[id],start_ts,end_ts FROM workout_sessions s WHERE edited;
UPDATE workout_sessions SET last_edit='legacy-label-'||id WHERE edited;
