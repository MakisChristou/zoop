-- Synthetic performance/UI fixture. Apply only to a fresh isolated development database.
INSERT INTO devices(id,model) VALUES('UI-REVIEW','TEST') ON CONFLICT DO NOTHING;
INSERT INTO profiles(device_id,sex,birth_year,weight_kg,tz) VALUES('UI-REVIEW','male',1985,80,'UTC') ON CONFLICT DO NOTHING;
INSERT INTO raw_frames(device_id,client_seq,channel,received_at,bytes,decoded_proto,decode_status) VALUES('UI-REVIEW',1,5,now(),'\x00',3,'unknown') ON CONFLICT DO NOTHING;
INSERT INTO samples(device_id,ts,hr,steps,activity,skin_temp_c,band_state,raw_frame_id)
SELECT 'UI-REVIEW',date_trunc('day',now())-make_interval(days=>d)+interval '8 hours'+make_interval(secs=>n),
 (60+n%90)::smallint,n%500,(n%3)::smallint,32+(n%5)*0.1,0,(SELECT id FROM raw_frames WHERE device_id='UI-REVIEW' LIMIT 1)
FROM generate_series(0,2799)n CROSS JOIN generate_series(0,364)d ON CONFLICT DO NOTHING;
INSERT INTO sleep_sessions(device_id,start_ts,end_ts,kind,detected_kind,timezone,metrics)
SELECT 'UI-REVIEW',onset,wake,'main','main','UTC',jsonb_build_object('sleep',jsonb_build_object(
 'algo_version',2,'window',jsonb_build_object('onset',onset,'offset',wake,'time_in_bed_s',28800,'asleep_s',27000+d%5*120,'waso_s',1800-d%5*120,'efficiency',0.94,'coverage_s',28800,'disturbances',2),
 'physiology',jsonb_build_object('resting_hr',50+d%7,'hrv_rmssd_ms',50+d%15,'hrv_windows',90,'respiratory_rate',15.0+d%3*0.1,'skin_temp_c',32.3,'spo2_windows',0),
 'naps','[]'::jsonb,'segments',jsonb_build_array(jsonb_build_object('stage','light','start',onset,'end',wake))
)) FROM (SELECT d,date_trunc('day',now())-make_interval(days=>d)-interval '1 hour' onset,date_trunc('day',now())-make_interval(days=>d)+interval '7 hours' wake FROM generate_series(0,364)d) t;
INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name)
SELECT 'UI-REVIEW','health:fixture-'||d,date_trunc('day',now())-make_interval(days=>d)+interval '9 hours',75+3*sin(d::float/25),'health','Test scale' FROM generate_series(0,729)d;
ANALYZE samples;
