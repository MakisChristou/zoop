-- Explicit phases retain legacy cut identities and archived settings.
ALTER TABLE weight_goals ADD COLUMN phase text NOT NULL DEFAULT 'cut' CHECK (phase IN ('cut','bulk','maintenance'));
ALTER TABLE weight_goals ADD COLUMN maintenance_reference_kg double precision CHECK (maintenance_reference_kg BETWEEN 20 AND 400);
ALTER TABLE weight_goals ADD COLUMN maintenance_range_pct double precision NOT NULL DEFAULT 1 CHECK (maintenance_range_pct BETWEEN 0.5 AND 5);
ALTER TABLE weight_goals DROP CONSTRAINT weight_goals_weekly_loss_kg_check;
ALTER TABLE weight_goals ADD CHECK ((phase='maintenance' AND weekly_loss_kg=0 AND finish_date IS NULL) OR (phase IN ('cut','bulk') AND weekly_loss_kg BETWEEN 0.05 AND 1));

CREATE OR REPLACE FUNCTION closed_goal_target(device text, settings jsonb, ended timestamptz)
RETURNS double precision LANGUAGE sql STABLE AS $$
 WITH baseline AS (
  SELECT kg FROM weight_readings WHERE device_id=device AND NOT removed AND kg BETWEEN 20 AND 400
   AND measured_at < ended AND measured_at >= (((settings->>'started_at')::timestamptz AT TIME ZONE (settings->>'timezone'))::date::timestamp AT TIME ZONE (settings->>'timezone'))
  ORDER BY (measured_at AT TIME ZONE (settings->>'timezone'))::date, (source='health') DESC, measured_at DESC,id DESC LIMIT 1
 ), target AS (
 SELECT kg + CASE WHEN settings->>'phase'='bulk' THEN 1 ELSE -1 END * (settings->>'weekly_loss_kg')::double precision *
 ((settings->>'finish_date')::date-((settings->>'started_at')::timestamptz AT TIME ZONE (settings->>'timezone'))::date)/7.0 AS kg FROM baseline
 ) SELECT kg FROM target WHERE kg BETWEEN 20 AND 400 AND coalesce(settings->>'phase','cut') <> 'maintenance'
$$;
CREATE OR REPLACE FUNCTION preserve_weight_goal_period() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ended timestamptz;
BEGIN
 IF OLD.active AND (NOT NEW.active OR NEW.started_at <> OLD.started_at) THEN
  ended := CASE WHEN NEW.started_at <> OLD.started_at THEN NEW.started_at ELSE NEW.updated_at END;
  INSERT INTO weight_goal_history(id,device_id,started_at,ended_at,end_reason,settings,target_weight_kg)
  VALUES(OLD.id,OLD.device_id,OLD.started_at,ended,
   CASE WHEN OLD.finish_date IS NOT NULL AND ended >= ((OLD.finish_date+1)::timestamp AT TIME ZONE OLD.timezone) THEN 'scheduled' ELSE 'manual' END,
   to_jsonb(OLD),closed_goal_target(OLD.device_id,to_jsonb(OLD),ended)) ON CONFLICT(id) DO NOTHING;
 END IF;
 IF NEW.started_at <> OLD.started_at THEN NEW.id := nextval(pg_get_serial_sequence('weight_goals','id')); END IF;
 RETURN NEW;
END $$;
-- Do not manufacture maintenance history before this feature exists.
WITH changed AS (
 UPDATE weight_goals SET phase='maintenance',active=true,weekly_loss_kg=0,finish_date=NULL,daily_steps_goal=NULL,
 started_at=now(),pace_started_at=now(),updated_at=now(),revision=revision+1 WHERE NOT active RETURNING *
) INSERT INTO weight_goal_revisions SELECT device_id,revision,to_jsonb(changed) FROM changed;
