WITH s AS (
               SELECT (ts AT TIME ZONE $2)::date AS day, ts, hr, steps, activity, skin_temp_c, band_state,
                      steps - lag(steps) OVER (ORDER BY ts) AS inc
               FROM samples WHERE device_id = $1
             ), d AS (
               SELECT day,
                      sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4)::int AS steps,
                      sum(inc) FILTER (WHERE inc BETWEEN 0 AND $4 AND activity IN (1, 2))::bigint AS steps_walking,
                      count(*) FILTER (WHERE activity IN (1, 2))::bigint AS walking_s,
                      min(hr) FILTER (WHERE hr > 0) AS hr_min,
                      avg(hr) FILTER (WHERE hr > 0)::real AS hr_avg,
                      max(hr) AS hr_max,
                      avg(skin_temp_c)::real AS skin_temp_avg,
                      count(*) FILTER (WHERE band_state = 2)::bigint AS asleep_s,
                      count(*)::bigint AS samples
               FROM s GROUP BY day ORDER BY day DESC LIMIT $3
             )
             SELECT d.day, d.steps, d.steps_walking, d.walking_s, d.hr_min, d.hr_avg, d.hr_max,
                    d.skin_temp_avg, d.asleep_s, d.samples,
                    st.load, st.trimp, st.kcal, st.zones_min
             FROM d LEFT JOIN strains st
               ON st.device_id = $1 AND st.day = d.day AND st.algo_version = coalesce(
                 (SELECT max(j.algo_version) FROM analysis_jobs j WHERE j.device_id=$1 AND j.kind='workout'
                  AND j.day=d.day AND j.tz=$2 AND j.completed_generation>0 AND j.algo_version<=$5),1)
             ORDER BY d.day