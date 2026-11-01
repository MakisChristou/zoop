-- Health projections own their identities and versions independently of analysis.
-- A per-device transactional counter prevents out-of-order commits skipping changes.
CREATE TABLE health_datasets (
 device_id TEXT PRIMARY KEY REFERENCES devices(id), namespace UUID NOT NULL DEFAULT gen_random_uuid(),
 cursor BIGINT NOT NULL DEFAULT 0
);
CREATE TABLE health_exports (
 device_id TEXT NOT NULL REFERENCES devices(id), id TEXT NOT NULL, domain TEXT NOT NULL,
 version BIGINT NOT NULL, sequence BIGINT NOT NULL, start_ts TIMESTAMPTZ NOT NULL,
 end_ts TIMESTAMPTZ NOT NULL, payload JSONB NOT NULL, removed BOOLEAN NOT NULL,
 PRIMARY KEY(device_id,id)
);
CREATE TABLE health_changes (LIKE health_exports INCLUDING DEFAULTS);
ALTER TABLE health_changes ADD PRIMARY KEY(device_id,sequence);
CREATE INDEX health_change_identity ON health_changes(device_id,id,sequence DESC);
CREATE TABLE weight_readings (
 device_id TEXT NOT NULL REFERENCES devices(id), id TEXT NOT NULL,
 measured_at TIMESTAMPTZ NOT NULL, kg DOUBLE PRECISION NOT NULL CHECK(kg BETWEEN 20 AND 400),
 source TEXT NOT NULL CHECK(source IN ('snoop','health')), source_name TEXT NOT NULL,
 version BIGINT NOT NULL DEFAULT 1, removed BOOLEAN NOT NULL DEFAULT false,
 PRIMARY KEY(device_id,id)
);
CREATE INDEX weight_dates ON weight_readings(device_id,measured_at);

CREATE FUNCTION publish_health(d TEXT, identity TEXT, category TEXT, a TIMESTAMPTZ,
 b TIMESTAMPTZ, data JSONB, gone BOOLEAN) RETURNS void LANGUAGE plpgsql AS $$
DECLARE old health_exports; counter BIGINT;
BEGIN
 INSERT INTO health_datasets(device_id) VALUES(d) ON CONFLICT DO NOTHING;
 PERFORM 1 FROM health_datasets WHERE device_id=d FOR UPDATE;
 SELECT * INTO old FROM health_exports WHERE device_id=d AND id=identity;
 IF FOUND AND old.start_ts=a AND old.end_ts=b AND old.payload=data AND old.removed=gone THEN RETURN; END IF;
 UPDATE health_datasets SET cursor=cursor+1 WHERE device_id=d RETURNING cursor INTO counter;
 INSERT INTO health_exports VALUES(d,identity,category,coalesce(old.version,0)+1,counter,a,b,data,gone)
 ON CONFLICT(device_id,id) DO UPDATE SET version=EXCLUDED.version,sequence=EXCLUDED.sequence,
 start_ts=EXCLUDED.start_ts,end_ts=EXCLUDED.end_ts,payload=EXCLUDED.payload,removed=EXCLUDED.removed;
 INSERT INTO health_changes SELECT * FROM health_exports WHERE device_id=d AND id=identity;
END $$;

CREATE FUNCTION project_health_session() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE category TEXT; data JSONB; periods JSONB;
BEGIN
 category := CASE WHEN TG_TABLE_NAME='sleep_sessions' THEN 'sleep' ELSE 'workout' END;
 IF NEW.status<>'active' THEN
  PERFORM publish_health(NEW.device_id,category||':'||NEW.id,category,NEW.start_ts,NEW.end_ts,'{}',true);
  RETURN NEW;
 END IF;
 IF NEW.metrics_pending OR NEW.end_ts>now() THEN RETURN NEW; END IF;
 IF category='sleep' THEN
  -- No early export of an ongoing sleep. Awake evidence uses the existing morning
  -- insight gate; explicit corrected bounds are already confirmed by the person.
  IF NOT NEW.fixed AND NOT (SELECT count(*) FILTER(WHERE band_state IN (0,3))>=1500
   FROM samples WHERE device_id=NEW.device_id AND ts>=NEW.end_ts AND ts<NEW.end_ts+interval '30 minutes')
  THEN RETURN NEW; END IF;
  -- Same one-second band-state accounting as selected_window; never bridge unknowns.
  WITH seconds AS (
   SELECT ts,ts-row_number() OVER(ORDER BY ts)*interval '1 second' AS island
   FROM samples WHERE device_id=NEW.device_id AND ts>=NEW.start_ts AND ts<NEW.end_ts AND band_state=2
  ), runs AS (SELECT min(ts) a,max(ts)+interval '1 second' b FROM seconds GROUP BY island)
  SELECT coalesce(jsonb_agg(jsonb_build_object('start',a,'end',b) ORDER BY a),'[]') INTO periods FROM runs;
  data:=jsonb_build_object('kind',NEW.kind,'intervals',periods);
 ELSE
  data:=jsonb_build_object('kind',NEW.kind);
 END IF;
 PERFORM publish_health(NEW.device_id,category||':'||NEW.id,category,NEW.start_ts,NEW.end_ts,data,false);
 RETURN NEW;
END $$;
CREATE TRIGGER health_sleep AFTER INSERT OR UPDATE ON sleep_sessions FOR EACH ROW EXECUTE FUNCTION project_health_session();
CREATE TRIGGER health_workout AFTER INSERT OR UPDATE ON workout_sessions FOR EACH ROW EXECUTE FUNCTION project_health_session();

CREATE FUNCTION project_health_weight() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 -- Imported objects keep their provenance and can never be re-exported.
 IF NEW.source='snoop' THEN
  PERFORM publish_health(NEW.device_id,'weight:'||NEW.id,'weight',NEW.measured_at,NEW.measured_at,
   jsonb_build_object('kg',NEW.kg),NEW.removed);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER health_weight AFTER INSERT OR UPDATE ON weight_readings FOR EACH ROW EXECUTE FUNCTION project_health_weight();

-- Step projections are refreshed only after the fenced daily publication. UTC minute
-- buckets have stable identities even across travel and daylight-saving transitions.
CREATE FUNCTION project_health_steps(d TEXT,a TIMESTAMPTZ,b TIMESTAMPTZ) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN
  WITH s AS (
   SELECT ts,activity,steps-lag(steps) OVER(ORDER BY ts) inc FROM samples
   WHERE device_id=d AND ts>=a-interval '1 second' AND ts<b
  ), counts AS (
   SELECT date_trunc('minute',ts) t,coalesce(sum(inc) FILTER(WHERE inc BETWEEN 0 AND 10 AND activity IN(1,2)),0)::bigint n
   FROM s WHERE ts>=a AND ts<b GROUP BY 1
  ) SELECT coalesce(c.t,e.start_ts) t,coalesce(c.n,0) n FROM counts c FULL JOIN
   (SELECT start_ts FROM health_exports WHERE device_id=d AND domain='steps' AND start_ts>=a AND start_ts<b) e ON e.start_ts=c.t
 LOOP
  IF r.t+interval '1 minute'>now() OR (r.n=0 AND NOT EXISTS(SELECT 1 FROM health_exports WHERE device_id=d AND id='steps:'||extract(epoch FROM r.t)::bigint)) THEN CONTINUE; END IF;
  PERFORM publish_health(d,'steps:'||extract(epoch FROM r.t)::bigint,'steps',r.t,r.t+interval '1 minute',jsonb_build_object('count',r.n),r.n=0);
 END LOOP;
END $$;
-- Bootstrap sessions without changing their analysis revisions. Steps bootstrap is
-- explicit/paged through the Health API so deploying does not reanalyse history.
UPDATE sleep_sessions SET revision=revision;
UPDATE workout_sessions SET revision=revision;
CREATE TABLE health_step_bootstraps(device_id TEXT NOT NULL REFERENCES devices(id), day DATE NOT NULL, PRIMARY KEY(device_id,day));
