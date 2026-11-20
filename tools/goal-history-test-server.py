"""Loopback-only synthetic Goals lifecycle fixture; never connects to a real server."""
import importlib.util
import copy
from pathlib import Path
from datetime import datetime, timezone, timedelta
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse
spec = importlib.util.spec_from_file_location("weekly", Path(__file__).with_name("weekly-weight-test-server.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
history = {}
def past(device):
    if device not in history:
        g=base.goal();g.update(id=100,started_at=base.stamp(base.now-timedelta(days=70)),updated_at=base.stamp(base.now-timedelta(days=42)),finish_date=str((base.now-timedelta(days=42)).date()))
        history[device]=[dict(id=100,goal=g,summary=base.summary(g),ended_at=base.stamp(base.now-timedelta(days=42)),end_reason="scheduled")]
    return history[device]
class Handler(base.Handler):
    def do_GET(self):
        path=urlparse(self.path).path
        parts=path.split("/")
        device=parts[3] if len(parts)>3 else ""
        g=base.goals.setdefault(device,base.goal());g.setdefault("id",1)
        if path.endswith("/weight-goals"):
            return self.send(dict(items=past(device),next_cursor=None))
        if "/weight-goals/" in path:
            p=next((p for p in past(device) if str(p["id"])==parts[-1]),None)
            return self.send(p,200 if p else 404)
        return super().do_GET()
    def do_PUT(self):
        if not self.path.endswith("/weight-goal"):return super().do_PUT()
        import json
        device=self.path.split("/")[3]
        q=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))))
        g=base.goals.setdefault(device,base.goal());g.setdefault("id",1)
        if q["revision"]!=g["revision"]:
            return self.send(dict(error=dict(message="Your goal changed. Refresh before saving.")),409)
        if g["active"] and not q["active"]:
            past(device).insert(0,dict(id=g["id"],goal=copy.deepcopy(g),summary=base.summary(g),ended_at=base.stamp(datetime.now(timezone.utc)),end_reason="manual"))
        if not g["active"] and q["active"]:
            g["id"]+=1;g["started_at"]=base.stamp(datetime.now(timezone.utc));g["pace_started_at"]=g["started_at"]
        g.update(q);g["revision"]+=1;g["updated_at"]=base.stamp(datetime.now(timezone.utc))
        self.send(g)
if __name__=="__main__":ThreadingHTTPServer(("127.0.0.1",28483),Handler).serve_forever()
