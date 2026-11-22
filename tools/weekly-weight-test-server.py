"""Loopback-only UI fixture. Every goal and measurement is synthetic."""
import json
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

now = datetime.now(timezone.utc)
stamp = lambda d: d.isoformat().replace('+00:00', 'Z')
goals = {}
def goal():
    return dict(revision=1, active=True, phase='cut', started_at=stamp(now-timedelta(days=28)),
                pace_started_at=stamp(now-timedelta(days=28)), timezone='UTC', weekly_loss_kg=.3,
                daily_steps_goal=8000, finish_date=str((now+timedelta(days=28)).date()), reminder_enabled=False, reminder_weekday=1, reminder_minute=1200, updated_at=stamp(now))
def summary(g):
    end=now.date()-timedelta(days=(now.weekday()+1)%7)
    weeks=[dict(start=str(end-timedelta(days=6+(3-i)*7)), end=str(end-timedelta(days=(3-i)*7)),
                median_kg=63.3-.3*i, count=6, eligible=True) for i in range(4)]
    return dict(algorithm_version=1, start=weeks[-1]['start'], end=weeks[-1]['end'], provisional=False,
                state='on_pace', reason='within_target', median_kg=62.4, change_kg=-.3,
                weekly_loss_kg=g['weekly_loss_kg'], count=6, week_number=4, weeks=weeks, progress=dict(weigh_ins=[dict(day=str(datetime.fromisoformat(g['started_at'].replace('Z','+00:00')).date()+timedelta(days=i)),kg=63.3-.9*i/27) for i in range(28)], finish_date=g.get('finish_date'), weeks_remaining=4 if g.get('finish_date') else None, completed=False, starting_weight_kg=63.3, current_weight_kg=62.4, total_lost_kg=.9, target_weight_kg=60.9 if g.get('finish_date') else None))
class Handler(BaseHTTPRequestHandler):
    def send(self, data, status=200):
        raw=json.dumps(data).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        path=urlparse(self.path).path;device=path.split('/')[3] if len(path.split('/'))>3 else ''
        if path.endswith('/weight-goals'):return self.send(dict(items=[],next_cursor=None))
        if path.endswith('/weight-goal'):
            if device.startswith('EMPTY-'):return self.send(dict(goal=None,summary=None))
            if device.startswith('ERROR-'):return self.send(dict(error='Temporarily unavailable'),500)
            g=goals.setdefault(device,goal())
            if device.startswith(('BULK-', 'MAINTENANCE-')) or g.get('phase') in ('bulk','maintenance'):
                import math
                phase = g.get('phase') if g.get('phase') in ('bulk','maintenance') else 'bulk' if device.startswith('BULK-') else 'maintenance'
                if g['phase']=='cut': g.update(phase=phase, weekly_loss_kg=.2 if phase=='bulk' else 0, finish_date=g.get('finish_date') if phase=='bulk' else None, maintenance_reference_kg=64, maintenance_range_pct=1, daily_steps_goal=10000)
                s=summary(g);s.update(algorithm_version=2,state='on_pace' if g['phase']=='bulk' else 'stable',trend_kg_per_week=.2 if g['phase']=='bulk' else 0,maintenance_lower_kg=63.36 if g['phase']=='maintenance' else None,maintenance_upper_kg=64.64 if g['phase']=='maintenance' else None)
                for i,w in enumerate(s['weeks']): w['median_kg']=64+i*.2 if g['phase']=='bulk' else 64
                for i,w in enumerate(s['progress']['weigh_ins']): w['kg']=64+i*.2/7 if g['phase']=='bulk' else 64+.08*math.sin(i)
                s['progress'].update(starting_weight_kg=64,current_weight_kg=s['progress']['weigh_ins'][-1]['kg'],total_lost_kg=64-s['progress']['weigh_ins'][-1]['kg'],target_weight_kg=65.6 if g['phase']=='bulk' else None,finish_date=g.get('finish_date'))
                return self.send(dict(goal=g,summary=s))
            if device.startswith('PAUSED-'):g['active']=False
            if device.startswith('OPEN-'):g['finish_date']=None
            if device.startswith('FIRST-'):
                g['started_at']=stamp(now-timedelta(days=1));g['pace_started_at']=g['started_at']
                monday=now.date()-timedelta(days=now.weekday())
                s=summary(g);s.update(start=str(monday),end=str(monday+timedelta(days=6)),state='starting',reason='first_week',median_kg=64.6,change_kg=None,count=1,week_number=1,provisional=True)
                s['weeks']=[dict(start=s['start'],end=s['end'],median_kg=64.6,count=1,eligible=False)]
                s['progress'].update(weigh_ins=[dict(day=str((now-timedelta(days=1)).date()),kg=70.6),dict(day=str(now.date()),kg=69.9)],starting_weight_kg=70.6,current_weight_kg=69.9,total_lost_kg=.7,target_weight_kg=67.7)
                s['median_kg']=70.25;s['count']=2;s['weeks'][0].update(median_kg=70.25,count=2)
                return self.send(dict(goal=g,summary=s))
            return self.send(dict(goal=g,summary=summary(g) if g['active'] and not device.startswith('PENDING-') else None))
        if path.endswith('/health'):return self.send(dict(namespace='WEEKLY-UI',cursor=0,earliest=None,wake_at=None))
        if path.endswith('/weight-changes'):return self.send(dict(rows=[dict(id='health:weekly-test',measured_at=stamp(now),kg=62.4,source='health',source_name='Test scale',version=1,removed=False)],next_cursor=1,watermark=1,done=True))
        if path.endswith('/steps'):
            hours=[0]*24;hours[9]=2200;hours[13]=5800 if device.startswith(('COMPLETE-', 'BULK-', 'MAINTENANCE-')) else 3400
            total=sum(hours)
            return self.send(dict(day=path.split('/')[-2],hours=hours,walking_hours=hours,total=total,walking=total,bouts=[]))
        if path.endswith(('/days','/nights','/minutes','/sessions')):return self.send([])
        return self.send({},404)
    def do_PUT(self):
        data=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        if self.path.endswith('/weight-goal'):
            device=self.path.split('/')[3];g=goals.setdefault(device,goal());g.update(data);g['revision']+=1;g['updated_at']=stamp(datetime.now(timezone.utc));return self.send(g)
        return self.send({},404)
    def log_message(self,*args):pass
if __name__=='__main__':ThreadingHTTPServer(('127.0.0.1',28482),Handler).serve_forever()
