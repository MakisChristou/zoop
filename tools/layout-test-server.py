"""Loopback-only, generated history for layout/gesture tests. No real health data.

Run alongside ZoopUITests on a simulator. The default test URL is port 28476.
All mutations are in memory and disappear when the process exits.
"""
import json
import math
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)


def stamp(value):
    return value.isoformat().replace('+00:00', 'Z')


nights, days, sessions, weights = [], [], [], []
for i in range(120):
    day = today - timedelta(days=i)
    end = day + timedelta(hours=8)
    start = end - timedelta(hours=7.5 + math.sin(i) / 2)
    seconds = int((end - start).total_seconds())
    window = dict(onset=stamp(start), offset=stamp(end), time_in_bed_s=seconds,
                  asleep_s=seconds-300, waso_s=300, efficiency=.98 if i == 0 else .97, coverage_s=seconds, disturbances=1)
    physiology = dict(resting_hr=55+math.sin(i)*3, hrv_rmssd_ms=65+math.cos(i)*10,
                      hrv_windows=120, respiratory_rate=14.3, skin_temp_c=33.4, spo2_pct=98, spo2_windows=60)
    stages = dict(wake_s=300, light_s=seconds-9600, deep_s=4200, rem_s=5100,
                  sleep_latency_s=300, rem_latency_s=5400, epochs=seconds//30, epochs_with_cardiac=seconds//30)
    segments = [dict(stage='light', start=stamp(start), end=stamp(start+timedelta(hours=2))),
                dict(stage='deep', start=stamp(start+timedelta(hours=2)), end=stamp(start+timedelta(hours=3))),
                dict(stage='rem', start=stamp(start+timedelta(hours=3)), end=stamp(end))]
    nights.append(dict(night_of=day.date().isoformat(), algo_version=2, start_ts=stamp(start), end_ts=stamp(end),
                       stages=segments, metrics=dict(window=window, physiology=physiology, stages=stages, naps=[])))
    sessions.append(dict(id=i+1, start_ts=stamp(start), end_ts=stamp(end), duration_s=seconds,
                         kind='main', edited=False, auto_detected=True, revision=1, status='active',
                         replacements=[], metrics_pending=False, timezone='UTC',
                         sleep=dict(window=window, physiology=physiology, stages=stages,
                                    segments=segments, algo_version=2, efficiency=.98 if i == 0 else .97)))
    days.append(dict(day=day.date().isoformat(), steps=9000+i*10, steps_walking=8200+i*10,
                     walking_s=3600, hr_min=51, hr_avg=69, hr_max=132, skin_temp_avg=33.4,
                     asleep_s=seconds-300, samples=80000, load=8.4, trimp=40, kcal=360, zones_min=[20,15,4,1,0]))
    # Today has a manual reading so the manual-entry test can replace it. Historical
    # readings exercise Health imports; their Health-first preference is unchanged.
    source = 'snoop' if i == 0 else 'health'
    weights.append(dict(id=f'{source}:layout-{i}', measured_at=stamp(day+timedelta(hours=7)),
                        kg=75.2+i*.02+math.sin(i)*.3, source=source, source_name='Zoop' if i == 0 else 'Test scale', version=1, removed=False))


# Independent device scopes let entry tests exercise empty and completed days.
weight_devices = {}
def weight_rows(device):
    if device not in weight_devices:
        rows = [dict(row) for row in weights]
        if device.startswith('WEIGHT-EMPTY-'):
            rows = [row for row in rows if row['id'] != 'snoop:layout-0']
        elif device.startswith('WEIGHT-HEALTH-'):
            rows[0].update(id='health:layout-0', source='health', source_name='Test scale')
        weight_devices[device] = rows
    return weight_devices[device]


def insight(day, mature=False, early_count=11):
    count = 14 if mature else early_count
    metrics = []
    for key, value, delta, unit in [('sleep', 28020, 2520, 'seconds'), ('hrv', 72, 18, 'percent'), ('resting_hr', 54, -3, 'bpm')]:
        metrics.append(dict(key=key, value=value, quality='good', relation='similar' if mature else None,
                            baseline=dict(state='established' if mature else 'early', count=count,
                                          **{'from': (today-timedelta(days=count)).date().isoformat(), 'to': (datetime.fromisoformat(day).date()-timedelta(days=1)).isoformat()},
                                          average=value*.95, lower=value*.9, upper=value*1.1),
                            comparison=dict(delta=delta, unit=unit, signal='favourable' if mature else None),
                            history=[dict(day=(today-timedelta(days=i)).date().isoformat(), value=value*(1+.03*math.sin(i))) for i in reversed(range(14))],
                            week=dict(count=7, average=value, previous_average=value*.95)))
    return dict(outlook=dict(state='good' if mature else 'learning', level=5 if mature else None,
                             baseline_count=count, baseline_required=14), version=1, day=day, timezone='UTC',
                state='ready', sleep_id=1, sleep_revision=1, metrics=metrics, observations=[],
                timing=dict(count=7, asleep_sd_min=25, wake_sd_min=20))


class Handler(BaseHTTPRequestHandler):
    def send(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        parts = url.path.strip('/').split('/')
        if len(parts) < 4 or parts[:2] != ['v1', 'devices']:
            return self.send({}, 404)
        device, route = parts[2], '/'.join(parts[3:])
        query = parse_qs(url.query)
        limit = int(query.get('limit', ['120'])[0])
        if route == 'sleeps': return self.send(nights[:limit])
        if route == 'progress':
            sparse = device == 'PROGRESS-SPARSE'
            metrics = []
            for key, current, previous, weeks, required in [
                ('sleep', 26640, 25560, [25020, 26100, 25200, 25920, 26280, 27000, 26400, 26880], 21),
                ('wake_variation', 24, 44, [44]*4+[24]*4, 21),
                ('steps', 7800, 6600, [6200, 6900, 6700, 6600, 7300, 8000, 7700, 8200], 21),
                ('walking', 142, 114, [114]*4+[142]*4, 3),
                ('strength', 2, 2, [2]*8, 3)]:
                count = 28 if required == 21 else 4
                sparse_count = 5 if required == 21 else 0
                visible_current = None if sparse and sparse_count == 0 else current
                metrics.append(dict(key=key, current=visible_current, previous=None if sparse else previous,
                                    change=None if sparse else current-previous, current_count=sparse_count if sparse else count,
                                    previous_count=0 if sparse else count, required_count=required,
                                    weeks=[None]*7+[visible_current] if sparse else weeks))
            return self.send(dict(timezone='UTC', current=dict(start=(today-timedelta(days=28)).date().isoformat(), end=(today-timedelta(days=1)).date().isoformat()),
                                  previous=dict(start=(today-timedelta(days=56)).date().isoformat(), end=(today-timedelta(days=29)).date().isoformat()), metrics=metrics))
        if route == 'days': return self.send(days[:limit])
        if route == 'workouts' or route.startswith('workouts/'):
            if not device.startswith('DESIGN-'): return self.send([])
            rows = [dict(id=900+i, start_ts=stamp(today-timedelta(days=i)+timedelta(hours=10)),
                                   end_ts=stamp(today-timedelta(days=i)+timedelta(hours=11)), duration_s=3600,
                                   kind=kind, detected_kind=kind, edited=False, auto_detected=True,
                                   load=7.2-i, avg_hr=112, max_hr=142, trimp=35, zones_min=[25,20,10,5,0],
                                   kcal=240, steps=5200 if kind == 'walk' else 150, revision=1, status='active',
                                   coverage_s=3600, hr_coverage_s=3600, timezone='UTC')
                              for i, kind in enumerate(['resistance', 'walk', 'resistance'])]
            if device.startswith('DESIGN-TIMELINE-'):
                rows = [dict(rows[i % 3], id=900+i,
                             start_ts=stamp(today-timedelta(days=day)+timedelta(hours=17-i%2*2)),
                             end_ts=stamp(today-timedelta(days=day)+timedelta(hours=17-i%2*2, minutes=duration)),
                             duration_s=duration*60, load=None if i == 7 else round(6.4+i*1.3, 1))
                        for i, (day, duration) in enumerate(zip([0,1,1,2,3,3,4,5,6,6], [49,64,37,72,45,58,31,52,63,41]))]
            if device.startswith('DESIGN-TIMELINE-EMPTY'): rows = []
            return self.send(rows if route == 'workouts' else next((w for w in rows if str(w['id']) == parts[-1]), {}))
        if route == 'sleep-sessions': return self.send(sessions[:limit])
        if route.endswith('/epochs'):
            if not device.startswith('DESIGN-'): return self.send([])
            session = next((s for s in sessions if str(s['id']) == parts[-2]), sessions[0])
            start = datetime.fromisoformat(session['start_ts'].replace('Z', '+00:00'))
            end = datetime.fromisoformat(session['end_ts'].replace('Z', '+00:00'))
            return self.send([dict(start=stamp(start+timedelta(seconds=i)), hr=55+4*math.sin(i/800),
                                   hr_variability=3, rmssd=65+12*math.cos(i/1200), resp_rate=14+0.7*math.sin(i/1600),
                                   move_frac=0.2 if i%2700<120 else 0.01, strap_awake=i%2700<120)
                              for i in range(0, int((end-start).total_seconds()), 30)])
        if route.startswith('sleep-sessions/'):
            return self.send(next((s for s in sessions if str(s['id']) == parts[-1]), {}))
        if route.endswith('/insights'):
            if device == 'SLEEP-COMPARISON': return self.send(dict(error='Synthetic insights unavailable'), 503)
            if device.startswith('MORNING-CARD-'):
                state = device.removeprefix('MORNING-CARD-')
                body = insight(parts[-2], state != 'learning')
                body['outlook'].update(state=state, level={'good':5,'average':3,'low':1}.get(state))
                if state in ('updating', 'awaiting_sync', 'no_sleep'):
                    body['state']=state; body['metrics']=[]
                if state in ('average', 'low'):
                    for metric in body['metrics']:
                        metric['comparison']['signal']='usual' if state == 'average' else 'unfavourable'
                return self.send(body)
            mature = device == 'INSIGHT-REVIEW' and parts[-2] == today.date().isoformat()
            return self.send(insight(parts[-2], mature, 13 if device == 'INSIGHT-REVIEW' else 11))
        if route.endswith('/steps'):
            hours = [0]*7 + [400, 1600, 0, 200, 800, 0, 0, 2000, 1200, 0, 2000] + [0]*6
            return self.send(dict(day=parts[-2], hours=hours, walking_hours=hours, total=sum(hours), walking=sum(hours), bouts=[]))
        if route.startswith('days/'):
            day = datetime.fromisoformat(parts[4]).replace(tzinfo=timezone.utc)
            return self.send([dict(ts=stamp(day+timedelta(minutes=m)), hr=65+int(10*math.sin(m/40)), hr_min=55,
                                   hr_max=85, skin_temp_c=33.4, steps=4, band_state=2 if m<480 else 0, activity=0)
                              for m in range(0, 1440, 5)])
        if route == 'profile': return self.send(dict(sex='male', birth_year=1985, height_cm=180, tz='UTC', weight_kg=75.2,
                                                     weight_measured_at=weights[0]['measured_at'], weight_source='health', weight_source_name='Test scale'))
        if route == 'health': return self.send(dict(namespace='LAYOUT-UI', cursor=0, earliest=stamp(today-timedelta(days=120)), wake_at=None))
        if route == 'health/exports': return self.send(dict(namespace='LAYOUT-UI', watermark=0, next_cursor=0, done=True, records=[]))
        if route == 'weight-changes': return self.send(dict(rows=weight_rows(device), next_cursor=len(weight_rows(device)), watermark=len(weight_rows(device)), done=True))
        if route == 'weights': return self.send(weight_rows(device))
        if route == 'processing': return self.send(dict(pending_decode=0, decode_failures=0, pending_analysis=0, failed_analysis=0, workers_healthy=True, paused=False))
        return self.send({'error': {'message': 'Unused synthetic endpoint'}}, 404)

    def do_PUT(self):
        row = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        if self.path.endswith('/weights'):
            row['version'] = row.get('version', 0) + 1
            readings = weight_rows(self.path.strip('/').split('/')[2])
            readings[:] = [r for r in readings if r['id'] != row['id']]
            readings.insert(0, row)
        self.send(row)

    def log_message(self, *_): pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 28476), Handler).serve_forever()
