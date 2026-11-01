INSERT INTO devices(id,model) VALUES('UI-REVIEW','TEST') ON CONFLICT DO NOTHING;
INSERT INTO profiles(device_id,sex,birth_year,weight_kg,tz) VALUES('UI-REVIEW','male',1985,80,'Asia/Nicosia') ON CONFLICT DO NOTHING;
INSERT INTO profile_revisions(device_id,effective_at,profile) SELECT device_id,'-infinity',to_jsonb(p) FROM profiles p;
INSERT INTO raw_frames(device_id,client_seq,channel,received_at,bytes,decoded_proto,decode_status) VALUES('UI-REVIEW',1,5,now(),'\x00',3,'unknown') ON CONFLICT DO NOTHING;
INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id)
 SELECT 'UI-REVIEW',date_trunc('day',now())-make_interval(days=>d)+interval '7 hours'+make_interval(secs=>n),
 CASE WHEN n<1500 OR n>=2700 THEN 140 ELSE 75 END,ARRAY[500],0,0,0,(SELECT id FROM raw_frames WHERE device_id='UI-REVIEW' LIMIT 1)
 FROM generate_series(0,4499)n CROSS JOIN generate_series(1,2)d ON CONFLICT DO NOTHING;
INSERT INTO samples(device_id,ts,hr,rr_ms,steps,activity,band_state,raw_frame_id)
 SELECT 'UI-REVIEW',date_trunc('day',now())-interval '1 day'+interval '5 hours'+make_interval(secs=>n),110,ARRAY[545],n*2,1,0,(SELECT id FROM raw_frames WHERE device_id='UI-REVIEW' LIMIT 1)
 FROM generate_series(0,1799)n ON CONFLICT DO NOTHING;
