-- Separate sleep identities share the correction protocol, never the workout rows.
CREATE SEQUENCE sleep_session_ids;
CREATE TABLE sleep_sessions (LIKE workout_sessions INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING INDEXES);
ALTER TABLE sleep_sessions ALTER COLUMN id SET DEFAULT nextval('sleep_session_ids');
ALTER TABLE sleep_sessions ADD FOREIGN KEY(device_id) REFERENCES devices(id);
ALTER TABLE sleep_sessions ADD CHECK(kind IN ('main','nap'));
ALTER TABLE sleep_sessions ADD CHECK(status IN ('active','removed','superseded'));
ALTER TABLE sleep_sessions ADD CHECK(end_ts>start_ts);
CREATE TABLE sleep_corrections (LIKE workout_corrections INCLUDING ALL);
ALTER TABLE sleep_corrections ADD FOREIGN KEY(device_id) REFERENCES devices(id);
CREATE TABLE sleep_aliases (legacy_id BIGINT PRIMARY KEY,session_id BIGINT NOT NULL REFERENCES sleep_sessions(id));

INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,metrics)
SELECT s.device_id,s.start_ts,s.end_ts+interval '1 second','main','main',coalesce(p.tz,'UTC'),
 jsonb_build_object('sleep',s.metrics||jsonb_build_object('segments',s.stages,'algo_version',s.algo_version,'window',(s.metrics->'window')||jsonb_build_object('offset',s.end_ts+interval '1 second'),'efficiency',CASE WHEN (s.metrics->'window'->>'coverage_s')::bigint >= (s.metrics->'window'->>'time_in_bed_s')::bigint-120 THEN s.metrics->'window'->'efficiency' END),
 'coverage_s',s.metrics->'window'->'coverage_s')
FROM effective_sleeps s LEFT JOIN profiles p ON p.device_id=s.device_id;
INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,metrics)
SELECT s.device_id,(n->>'onset')::timestamptz,(n->>'offset')::timestamptz+interval '1 second','nap','nap',coalesce(p.tz,'UTC'),
 jsonb_build_object('sleep',jsonb_build_object('window',n||jsonb_build_object('offset',(n->>'offset')::timestamptz+interval '1 second'),'physiology','{"hrv_windows":0,"spo2_windows":0}'::jsonb,'segments','[]'::jsonb,'algo_version',s.algo_version),
 'coverage_s',n->'coverage_s')
FROM effective_sleeps s CROSS JOIN LATERAL jsonb_array_elements(coalesce(s.metrics->'naps','[]')) n
LEFT JOIN profiles p ON p.device_id=s.device_id;

-- The legacy night API stays readable while the new version catches up.
CREATE VIEW effective_sleep_sessions AS
 SELECT s.*, (end_ts AT TIME ZONE timezone)::date AS wake_day FROM sleep_sessions s WHERE status='active';
-- Reset history is independent of detector results and contains no raw sensor bytes.
CREATE TABLE analysis_resets (
 operation_id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id), request JSONB NOT NULL,
 snapshot JSONB NOT NULL, scope_start TIMESTAMPTZ NOT NULL, scope_end TIMESTAMPTZ NOT NULL,
 active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE VIEW effective_sleep_read AS
 SELECT s.device_id,s.wake_day AS night_of,coalesce((s.metrics->'sleep'->>'algo_version')::int,2) AS algo_version,
 s.start_ts,s.end_ts,coalesce(s.metrics->'sleep'->'segments','[]'::jsonb) AS stages,
 (s.metrics->'sleep')||jsonb_build_object('naps',coalesce((SELECT jsonb_agg(n.metrics->'sleep'->'window' ORDER BY n.start_ts) FROM effective_sleep_sessions n WHERE n.device_id=s.device_id AND n.kind='nap' AND n.wake_day=s.wake_day),'[]'::jsonb)) AS metrics
 FROM (SELECT DISTINCT ON(device_id,wake_day) * FROM effective_sleep_sessions WHERE kind='main' AND metrics->'sleep' IS NOT NULL ORDER BY device_id,wake_day,fixed DESC,duration_s DESC,id) s
 UNION ALL
 SELECT r.device_id,r.night_of,r.algo_version,r.start_ts,r.end_ts+interval '1 second',r.stages,r.metrics||jsonb_build_object('window',(r.metrics->'window')||jsonb_build_object('offset',r.end_ts+interval '1 second')) FROM effective_sleeps r WHERE NOT EXISTS(SELECT 1 FROM sleep_sessions s WHERE s.device_id=r.device_id);
