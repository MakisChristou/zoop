#!/usr/bin/env python3
"""Smoke-test a disposable, freshly started Compose project. Never use real data."""
import http.cookiejar
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
PROJECT = os.environ.get("COMPOSE_PROJECT_NAME", "")
assert PROJECT.startswith("zoop-test-") or PROJECT == "zoop-compose-check", "Use a disposable zoop-test-* project"
CONFIG = dict(line.split("=", 1) for line in (ROOT / ".env").read_text().splitlines() if line and not line.startswith("#"))
ORIGIN = os.environ.get("ZOOP_ORIGIN", CONFIG["ZOOP_ORIGIN"])
assert ORIGIN.startswith("http://127.0.0.1:"), "Test only a loopback HTTP installation"
PASSWORD = "synthetic compose test password"


def compose(*args, input=None, env=None, check=True):
    return subprocess.run(["docker", "compose", *args], cwd=ROOT,
                          env={**os.environ, **(env or {})}, input=input,
                          capture_output=True, check=check)


def request(path, body=None, expected=200, client=None, origin=ORIGIN):
    headers = {"Origin": origin}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(ORIGIN + path, json.dumps(body).encode() if body is not None else None, headers)
    try:
        response = (client or urllib.request.build_opener()).open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    assert response.status == expected, f"{path}: expected {expected}, got {response.status}"
    data = response.read()
    return json.loads(data) if data and data[:1] in (b"{", b"[") else data, response.headers


assert request("/v1/setup")[0]["available"] is True
request("/v1/admin/stats", expected=401)
payload = {"code": CONFIG["ZOOP_SETUP_CODE"], "email": "owner@example.test", "password": PASSWORD, "device": "COMPOSE-OWNER"}
request("/v1/setup", {**payload, "code": "wrong"}, expected=401)
request("/v1/setup", payload, origin="http://attacker.test", expected=403)
request("/v1/setup", payload, expected=201)
assert request("/v1/setup")[0]["available"] is False
request("/v1/setup", payload, expected=404)

owner = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
_, headers = request("/v1/auth/login", {"email": payload["email"], "password": PASSWORD}, client=owner)
cookie = headers["Set-Cookie"]
assert "HttpOnly" in cookie and "SameSite=Strict" in cookie and "Secure" not in cookie
assert request("/v1/auth/me", client=owner)[0]["devices"] == ["COMPOSE-OWNER"]
assert request("/v1/auth/me", client=owner)[0]["pending_devices"] == ["COMPOSE-OWNER"]
request("/v1/admin/stats", client=owner)
request("/v1/devices/NOT-OWNED/profile", client=owner, expected=404)
request("/v1/auth/logout", {}, client=owner, origin="http://attacker.test", expected=403)

# Operator creation through stdin does not put the password in process arguments.
compose("exec", "-T", "api", "/usr/local/bin/zoop", "--config", "/etc/zoop/zoop.toml", "account", "create", "--email", "member@example.test", "--password-file", "-", input=PASSWORD.encode())
compose("exec", "-T", "api", "/usr/local/bin/zoop", "--config", "/etc/zoop/zoop.toml", "account", "bind-device", "--email", "member@example.test", "--device", "COMPOSE-MEMBER")
member = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
request("/v1/auth/login", {"email": "member@example.test", "password": PASSWORD}, client=member)
request("/v1/admin/stats", client=member, expected=403)
request("/v1/devices/COMPOSE-OWNER/profile", client=member, expected=404)
assert request("/v1/auth/me", client=member)[0]["devices"] == ["COMPOSE-MEMBER"]

compose("restart", "api", "web")
compose("up", "-d", "--wait")
assert request("/v1/setup")[0]["available"] is False
request("/v1/auth/me", client=owner)

# A backup cannot overwrite a file and restoration cannot overwrite a live database.
backup = ROOT / "backups/compose-test.dump"
backup.parent.mkdir(exist_ok=True)
subprocess.run(["sh", "tools/backup.sh", str(backup)], cwd=ROOT, check=True, capture_output=True)
assert backup.stat().st_mode & 0o777 == 0o600
assert subprocess.run(["sh", "tools/backup.sh", str(backup)], cwd=ROOT, capture_output=True).returncode != 0
assert subprocess.run(["sh", "tools/restore.sh", str(backup)], cwd=ROOT, capture_output=True).returncode != 0
restore_env = {**os.environ, "COMPOSE_PROJECT_NAME": PROJECT + "-restore", "ZOOP_PORT": "18081", "ZOOP_ORIGIN": "http://127.0.0.1:18081"}
try:
    compose("up", "-d", "--wait", "database", env=restore_env)
    subprocess.run(["sh", "tools/restore.sh", str(backup)], cwd=ROOT, env=restore_env, check=True, capture_output=True)
    compose("up", "-d", "--wait", env=restore_env)
    ORIGIN = restore_env["ZOOP_ORIGIN"]
    restored = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    assert request("/v1/setup")[0]["available"] is False
    request("/v1/auth/login", {"email": payload["email"], "password": PASSWORD}, client=restored, origin=ORIGIN)
    assert request("/v1/auth/me", client=restored)[0]["devices"] == ["COMPOSE-OWNER"]
    print("PASS: first setup, origin checks, account isolation, restart, backup and empty-database restore")
finally:
    compose("down", "-v", env=restore_env, check=False)
    backup.unlink(missing_ok=True)
