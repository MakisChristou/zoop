"""Synthetic, loopback-only API for MorningRefreshTests; no production data."""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

started = {}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = urlparse(self.path).path.split('/')
        if len(parts) == 7 and parts[1:3] == ['v1', 'devices'] and parts[4] == 'days' and parts[6] == 'insights':
            device = parts[3]
            first = started.setdefault(device, time.monotonic())
            state = 'updating' if time.monotonic() - first < 15 else 'ready'
            body = dict(version=2, day=parts[5], timezone='UTC', state=state, sleep_id=1,
                        sleep_revision=1, metrics=[], observations=[], timing=dict(count=0),
                        outlook=dict(state='learning' if state == 'ready' else state,
                                     baseline_count=10, baseline_required=14))
            status = 200
        else:
            # Other Today feeds must not block the independent morning refresh.
            body = {'error': {'message': 'Synthetic endpoint not used by this test'}}
            status = 404
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 28479), Handler).serve_forever()
