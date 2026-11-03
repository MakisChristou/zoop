"""Loopback fixture for ProfileUITests. All readings and photos are synthetic."""
import json
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

photos = {}
now = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
stamp = lambda d: d.isoformat().replace('+00:00', 'Z')
readings = [dict(id=f'health:profile-{i}', measured_at=stamp(now-timedelta(days=i)), kg=75.2+i/10,
                 source='health', source_name='Test scale', version=1, removed=False) for i in range(3)]


class Handler(BaseHTTPRequestHandler):
    def send(self, body, status=200, content_type='application/json'):
        data = json.dumps(body).encode() if content_type == 'application/json' else body
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parts = urlparse(self.path).path.split('/')
        device = parts[3] if len(parts)>3 else ''
        if self.path.endswith('/profile/photo'):
            return self.send(photos[device], content_type='image/jpeg') if device in photos else self.send({},404)
        if self.path.endswith('/profile'):
            return self.send(dict(sex='male', birth_year=1985, height_cm=180, tz='UTC', weight_kg=75.2,
                                  weight_measured_at=stamp(now), weight_source='health', weight_source_name='Test scale'))
        if self.path.endswith('/health'):
            return self.send(dict(namespace='PROFILE-UI', cursor=0, earliest=stamp(now-timedelta(days=30)), wake_at=None))
        if '/weight-changes' in self.path:
            return self.send(dict(rows=readings, next_cursor=3, watermark=3, done=True))
        if '/weights' in self.path:
            return self.send(readings)
        return self.send({'error': {'message':'Unused synthetic endpoint'}},404)

    def do_PUT(self):
        data=self.rfile.read(int(self.headers.get('Content-Length',0)))
        if self.path.endswith('/profile/photo'):
            photos[self.path.split('/')[3]]=data
            return self.send(data, content_type='image/jpeg')
        return self.send(json.loads(data))

    def do_DELETE(self):
        photos.pop(self.path.split('/')[3],None)
        self.send(b'',204,'image/jpeg')

    def log_message(self,*_):
        pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1',28480), Handler).serve_forever()
