-- Rebuildable read projections. Raw frames and samples remain the source of truth.
-- UTC day markers bound calendar-day discovery; cached results retain the caller's
-- timezone. Missing days are still omitted, as in the original days endpoint.
CREATE TABLE sample_days (
 device_id TEXT NOT NULL REFERENCES devices(id), day DATE NOT NULL,
 PRIMARY KEY(device_id,day)
);
INSERT INTO sample_days SELECT DISTINCT device_id,(ts AT TIME ZONE 'UTC')::date FROM samples;
CREATE TABLE day_summary_cache (
 device_id TEXT NOT NULL REFERENCES devices(id), tz TEXT NOT NULL, day DATE NOT NULL,
 start_ts TIMESTAMPTZ NOT NULL, end_ts TIMESTAMPTZ NOT NULL,
 dirty BOOLEAN NOT NULL DEFAULT true, generation BIGINT NOT NULL DEFAULT 0,
 steps INTEGER, steps_walking BIGINT, walking_s BIGINT,
 hr_min SMALLINT, hr_avg REAL, hr_max SMALLINT, skin_temp_avg REAL,
 asleep_s BIGINT, samples BIGINT NOT NULL DEFAULT 0,
 PRIMARY KEY(device_id,tz,day)
);
CREATE INDEX day_summary_intervals ON day_summary_cache(device_id,start_ts,end_ts);

-- A changed counter also changes the increment of its next sample, even across a
-- long missing-data gap. Invalidation and sample writes commit in one transaction.
CREATE FUNCTION invalidate_day_summaries(d TEXT, lo TIMESTAMPTZ, hi TIMESTAMPTZ)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE successor TIMESTAMPTZ;
BEGIN
 -- Cache creation must also be fenced: a not-yet-committed cache row cannot be
 -- found by UPDATE invalidation. The writer waits for the brief cache publication;
 -- competing readers use an uncached snapshot instead of waiting on this lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('snoop.day-summary.'||d,0));
 INSERT INTO sample_days SELECT d,g::date
 FROM generate_series((lo AT TIME ZONE 'UTC')::date::timestamp,
                      (hi AT TIME ZONE 'UTC')::date::timestamp,interval '1 day') g
 ON CONFLICT DO NOTHING;
 SELECT ts INTO successor FROM samples WHERE device_id=d AND ts>hi ORDER BY ts LIMIT 1;
 UPDATE day_summary_cache SET dirty=true,generation=generation+1
 WHERE device_id=d AND end_ts>lo AND start_ts<=coalesce(successor,hi);
END $$;
CREATE FUNCTION dirty_day_summaries_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT device_id,min(ts) lo,max(ts) hi FROM new_samples GROUP BY device_id ORDER BY device_id LOOP
  PERFORM invalidate_day_summaries(r.device_id,r.lo,r.hi);
 END LOOP;
 RETURN NULL;
END $$;
CREATE FUNCTION dirty_day_summaries_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT device_id,min(ts) lo,max(ts) hi FROM old_samples GROUP BY device_id ORDER BY device_id LOOP
  PERFORM invalidate_day_summaries(r.device_id,r.lo,r.hi);
 END LOOP;
 RETURN NULL;
END $$;
CREATE FUNCTION dirty_day_summaries_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT device_id,min(ts) lo,max(ts) hi FROM
  (SELECT device_id,ts FROM old_samples UNION ALL SELECT device_id,ts FROM new_samples) changed
  GROUP BY device_id ORDER BY device_id LOOP
  PERFORM invalidate_day_summaries(r.device_id,r.lo,r.hi);
 END LOOP;
 RETURN NULL;
END $$;
CREATE TRIGGER summaries_insert AFTER INSERT ON samples REFERENCING NEW TABLE AS new_samples
 FOR EACH STATEMENT EXECUTE FUNCTION dirty_day_summaries_insert();
CREATE TRIGGER summaries_delete AFTER DELETE ON samples REFERENCING OLD TABLE AS old_samples
 FOR EACH STATEMENT EXECUTE FUNCTION dirty_day_summaries_delete();
CREATE TRIGGER summaries_update AFTER UPDATE ON samples REFERENCING OLD TABLE AS old_samples NEW TABLE AS new_samples
 FOR EACH STATEMENT EXECUTE FUNCTION dirty_day_summaries_update();

CREATE FUNCTION refresh_day_summary(d TEXT, zone TEXT, local_day DATE)
RETURNS day_summary_cache LANGUAGE plpgsql AS $$
DECLARE result day_summary_cache; lo TIMESTAMPTZ; hi TIMESTAMPTZ; can_cache BOOLEAN;
BEGIN
 lo := local_day::timestamp AT TIME ZONE zone;
 hi := (local_day+1)::timestamp AT TIME ZONE zone;
 can_cache := pg_try_advisory_xact_lock(hashtextextended('snoop.day-summary.'||d,0));
 IF can_cache THEN
  INSERT INTO day_summary_cache(device_id,tz,day,start_ts,end_ts)
  VALUES(d,zone,local_day,lo,hi) ON CONFLICT DO NOTHING;
 END IF;
 -- Compute without holding cache locks during the sensor scan. The generation
 -- comparison below prevents a concurrent decode invalidation from being lost.
 SELECT * INTO result FROM day_summary_cache WHERE device_id=d AND tz=zone AND day=local_day;
 IF FOUND AND NOT result.dirty THEN RETURN result; END IF;
 IF result.device_id IS NULL THEN
  result.device_id:=d; result.tz:=zone; result.day:=local_day;
  result.start_ts:=lo; result.end_ts:=hi; result.generation:=0;
 END IF;
 WITH source AS (
  SELECT ts,hr,steps,activity,skin_temp_c,band_state FROM samples WHERE device_id=d AND ts>=lo AND ts<hi
  UNION ALL
  (SELECT ts,hr,steps,activity,skin_temp_c,band_state FROM samples WHERE device_id=d AND ts<lo ORDER BY ts DESC LIMIT 1)
 ), increments AS (
  SELECT *,steps-lag(steps) OVER(ORDER BY ts) inc FROM source
 ), totals AS (
  SELECT sum(inc) FILTER(WHERE inc BETWEEN 0 AND 10)::int steps,
         sum(inc) FILTER(WHERE inc BETWEEN 0 AND 10 AND activity IN(1,2))::bigint steps_walking,
         count(*) FILTER(WHERE activity IN(1,2))::bigint walking_s,
         min(hr) FILTER(WHERE hr>0) hr_min,avg(hr) FILTER(WHERE hr>0)::real hr_avg,max(hr) hr_max,
         avg(skin_temp_c)::real skin_temp_avg,count(*) FILTER(WHERE band_state=2)::bigint asleep_s,count(*)::bigint samples
  FROM increments WHERE ts>=lo
 ) SELECT steps,steps_walking,walking_s,hr_min,hr_avg,hr_max,skin_temp_avg,asleep_s,samples
 INTO result.steps,result.steps_walking,result.walking_s,result.hr_min,result.hr_avg,result.hr_max,
      result.skin_temp_avg,result.asleep_s,result.samples FROM totals;
 result.dirty := false;
 IF can_cache THEN
 UPDATE day_summary_cache c SET steps=result.steps,steps_walking=result.steps_walking,walking_s=result.walking_s,
 hr_min=result.hr_min,hr_avg=result.hr_avg,hr_max=result.hr_max,skin_temp_avg=result.skin_temp_avg,
 asleep_s=result.asleep_s,samples=result.samples,dirty=false
 WHERE c.device_id=d AND c.tz=zone AND c.day=local_day AND c.generation=result.generation;
 END IF;
 RETURN result;
END $$;
