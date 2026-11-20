-- A transactional per-device cursor follows both imported and Snoop weigh-ins.
-- Rows retain soft-deletion tombstones. Updating a row after a page watermark moves
-- it into the next pass, so an interrupted client can always resume without gaps.
CREATE TABLE weight_cursors(device_id TEXT PRIMARY KEY REFERENCES devices(id), cursor BIGINT NOT NULL DEFAULT 0);
ALTER TABLE weight_readings ADD COLUMN change_seq BIGINT NOT NULL DEFAULT 0;
WITH initial AS (SELECT device_id,id,row_number() OVER(PARTITION BY device_id ORDER BY id) seq FROM weight_readings)
UPDATE weight_readings w SET change_seq=i.seq FROM initial i WHERE w.device_id=i.device_id AND w.id=i.id;
INSERT INTO weight_cursors SELECT device_id,max(change_seq) FROM weight_readings GROUP BY device_id;
CREATE INDEX weight_change_cursor ON weight_readings(device_id,change_seq);
CREATE FUNCTION advance_weight_cursor() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'change_seq')=(to_jsonb(OLD)-'change_seq') THEN
  NEW.change_seq := OLD.change_seq; RETURN NEW;
 END IF;
 INSERT INTO weight_cursors(device_id) VALUES(NEW.device_id) ON CONFLICT DO NOTHING;
 UPDATE weight_cursors SET cursor=cursor+1 WHERE device_id=NEW.device_id RETURNING cursor INTO NEW.change_seq;
 RETURN NEW;
END $$;
CREATE TRIGGER weight_cursor BEFORE INSERT OR UPDATE ON weight_readings FOR EACH ROW EXECUTE FUNCTION advance_weight_cursor();
