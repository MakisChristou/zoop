-- Weight is a dated measurement, not an import-order overwrite of the body profile.
-- Recompute affected workout inputs through the existing generation-fenced queue.
CREATE FUNCTION refresh_weight_analysis() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE changed_at TIMESTAMPTZ;
BEGIN
 IF TG_OP='UPDATE' AND (NEW.measured_at,NEW.kg,NEW.source,NEW.removed)
   IS NOT DISTINCT FROM (OLD.measured_at,OLD.kg,OLD.source,OLD.removed) THEN
   RETURN NEW;
 END IF;
 changed_at := CASE WHEN TG_OP='UPDATE' THEN least(OLD.measured_at,NEW.measured_at) ELSE NEW.measured_at END;
 UPDATE analysis_jobs SET generation=generation+1,available_at=now(),backfill=true
 WHERE device_id=NEW.device_id AND kind='workout' AND day >= (changed_at AT TIME ZONE tz)::date;
 RETURN NEW;
END $$;
CREATE TRIGGER weight_analysis AFTER INSERT OR UPDATE ON weight_readings
 FOR EACH ROW EXECUTE FUNCTION refresh_weight_analysis();

-- Bring already-derived workout days onto the same measured-weight policy.
UPDATE analysis_jobs j SET generation=generation+1,available_at=now(),backfill=true
WHERE kind='workout' AND EXISTS (SELECT 1 FROM weight_readings w
 WHERE w.device_id=j.device_id AND NOT w.removed AND (w.measured_at AT TIME ZONE j.tz)::date<=j.day);
