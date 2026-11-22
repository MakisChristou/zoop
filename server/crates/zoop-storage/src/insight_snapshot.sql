WITH ranked AS (
 SELECT s.*, (end_ts AT TIME ZONE $4)::date AS day,
 count(*) OVER (PARTITION BY (end_ts AT TIME ZONE $4)::date,timezone,metrics #>> '{sleep,algo_version}') AS day_count,
 row_number() OVER (PARTITION BY (end_ts AT TIME ZONE $4)::date ORDER BY fixed DESC,duration_s DESC,id) AS rank
 FROM sleep_sessions s WHERE device_id=$1 AND status='active' AND kind='main'
 AND end_ts >= $2::date::timestamp AT TIME ZONE $4
 AND end_ts < ($3::date+1)::timestamp AT TIME ZONE $4
)
SELECT s.id,s.revision,s.day_count,s.day,s.timezone,s.start_ts,s.end_ts,s.duration_s,s.metrics,
 (NOT coalesce(e.boundary_complete OR s.fixed,false) AND EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='sleep' AND j.day=s.day AND j.algo_version=$5 AND j.generation>j.completed_generation) ) AS day_pending,
 (s.metrics_pending OR (e.session_id IS NULL AND EXISTS(SELECT 1 FROM analysis_jobs j WHERE j.device_id=s.device_id AND j.kind='sleep' AND j.algo_version=$5 AND j.day=(s.end_ts AT TIME ZONE s.timezone)::date AND j.tz=s.timezone AND j.generation>j.completed_generation)) ) AS pending,
 (s.fixed OR coalesce(e.boundary_complete, ((SELECT count(*)>=270 AND count(*) FILTER(WHERE band_state<>2)>=150
 FROM samples WHERE device_id=$1 AND ts>=s.start_ts-interval '5 minutes' AND ts<s.start_ts)
 AND (SELECT count(*)>=1500 AND count(*) FILTER(WHERE band_state IN (0,3))>=1500
 FROM samples WHERE device_id=$1 AND ts>=s.end_ts AND ts<s.end_ts+interval '30 minutes')))) AND s.end_ts<=now() AS complete,
 coalesce(e.hr_samples,(SELECT count(*) FROM samples WHERE device_id=$1 AND ts>=s.start_ts AND ts<s.end_ts AND hr IS NOT NULL)) AS hr_samples,
 (extract(epoch FROM (s.start_ts AT TIME ZONE s.timezone)::time)/60)::float8 AS onset_minute,
 (extract(epoch FROM (s.end_ts AT TIME ZONE s.timezone)::time)/60)::float8 AS wake_minute
FROM ranked s LEFT JOIN sleep_evidence e ON e.session_id=s.id AND e.revision=s.revision WHERE rank=1 ORDER BY day
