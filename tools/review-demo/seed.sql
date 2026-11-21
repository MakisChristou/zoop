-- Synthetic review data only. Refuses a personal or previously populated database.
\set ON_ERROR_STOP on
BEGIN;
DO $$
BEGIN
 IF current_database() <> 'zoop_review' THEN RAISE EXCEPTION 'requires dedicated zoop_review database'; END IF;
 IF EXISTS(SELECT 1 FROM devices) OR EXISTS(SELECT 1 FROM accounts) THEN
   RAISE EXCEPTION 'review seed requires an empty installation; no data was replaced';
 END IF;
END $$;
INSERT INTO devices(id,model) VALUES('ZOOP-REVIEW-SYNTHETIC','SYNTHETIC');
INSERT INTO profiles(device_id,sex,birth_year,weight_kg,height_cm,tz)
VALUES('ZOOP-REVIEW-SYNTHETIC','male',1990,75,180,'UTC');
DO $$
DECLARE d date; start_at timestamptz; end_at timestamptz; span integer; n integer;
        physiology jsonb; sleep_window jsonb; stages jsonb; segments jsonb; frame bigint;
BEGIN
 FOR n IN 0..55 LOOP
  d := current_date-n;
  end_at := (d::timestamp AT TIME ZONE 'UTC') + interval '7 hours';
  span := 27000 + (sin(n*0.9)*2400)::integer;
  start_at := end_at-make_interval(secs=>span);
  physiology := jsonb_build_object('resting_hr',55+sin(n)*3,'hrv_rmssd_ms',65+cos(n)*10,
     'hrv_windows',120,'respiratory_rate',14.3,'skin_temp_c',33.4,'spo2_pct',98,'spo2_windows',60);
  sleep_window := jsonb_build_object('onset',start_at,'offset',end_at,'time_in_bed_s',span,
     'asleep_s',span-900,'waso_s',900,'efficiency',(span-900)::float/span,'coverage_s',span,'disturbances',1);
  stages := jsonb_build_object('wake_s',900,'light_s',span-10200,'deep_s',4200,'rem_s',5100,
     'sleep_latency_s',300,'rem_latency_s',5400,'epochs',span/30,'epochs_with_cardiac',span/30);
  SELECT jsonb_agg(jsonb_build_object('stage',stage,'start',a,'end',b)) INTO segments FROM (VALUES
    ('light',start_at,start_at+interval '2 hours'),
    ('deep',start_at+interval '2 hours',start_at+interval '3 hours 10 minutes'),
    ('rem',start_at+interval '3 hours 10 minutes',start_at+interval '4 hours 35 minutes'),
    ('wake',start_at+interval '4 hours 35 minutes',start_at+interval '4 hours 50 minutes'),
    ('light',start_at+interval '4 hours 50 minutes',end_at)) v(stage,a,b);
  INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics)
  VALUES('ZOOP-REVIEW-SYNTHETIC',start_at,end_at,'main','main','UTC',true,
     jsonb_build_object('coverage_s',span,'sleep',jsonb_build_object('algo_version',5,'window',sleep_window,
       'physiology',physiology,'stages',stages,'segments',segments,'efficiency',(span-900)::float/span)));
  INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name)
  VALUES('ZOOP-REVIEW-SYNTHETIC','snoop:review-'||d,(d::timestamp AT TIME ZONE 'UTC')+interval '8 hours',
         75+n*.02+sin(n)*.25,'snoop','Synthetic review data');
  INSERT INTO raw_frames(device_id,client_seq,channel,received_at,bytes,decoded_proto)
  VALUES('ZOOP-REVIEW-SYNTHETIC',n+1,5,d::timestamp AT TIME ZONE 'UTC',decode('000000','hex'),32767) RETURNING id INTO frame;
  INSERT INTO samples(device_id,ts,hr,rr_ms,skin_temp_c,steps,activity,band_state,raw_frame_id)
  SELECT 'ZOOP-REVIEW-SYNTHETIC',(d::timestamp AT TIME ZONE 'UTC')+m*interval '1 minute',
    CASE WHEN m<420 THEN 55+(sin(m*.1)*3)::integer ELSE 72+(sin(m*.08)*12)::integer END,
    ARRAY[900,940],33.4,(m*7),CASE WHEN m>=420 THEN 1 ELSE 0 END,
    CASE WHEN m<420 THEN 2 ELSE 0 END,frame
  FROM generate_series(0,1439) m
  WHERE (d::timestamp AT TIME ZONE 'UTC')+m*interval '1 minute' < now();
  INSERT INTO strains(device_id,day,algo_version,load,trimp,zones_min)
  VALUES('ZOOP-REVIEW-SYNTHETIC',d,1,7+sin(n)*3,40,ARRAY[20,15,4,1,0]);
  IF n%2=0 THEN
    INSERT INTO workout_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,fixed,metrics)
    VALUES('ZOOP-REVIEW-SYNTHETIC',(d::timestamp AT TIME ZONE 'UTC')+interval '17 hours',
      (d::timestamp AT TIME ZONE 'UTC')+interval '17 hours 45 minutes',
      CASE WHEN n%4=0 THEN 'resistance' ELSE 'walk' END,
      CASE WHEN n%4=0 THEN 'resistance' ELSE 'walk' END,'UTC',true,
      '{"load":8,"avg_hr":110,"max_hr":145,"coverage_s":2700,"hr_coverage_s":2700,"trimp":35,"kcal":250,"steps":4200,"zones_min":[20,15,8,2,0]}');
  END IF;
 END LOOP;
END $$;
COMMIT;
