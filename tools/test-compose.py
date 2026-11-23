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


def request(path, body=None, expected=200, client=None, origin=ORIGIN, method=None, bearer=None):
    headers = {"Origin": origin}
    if bearer is not None:
        headers["Authorization"] = "Bearer " + bearer
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(ORIGIN + path, json.dumps(body).encode() if body is not None else None, headers, method=method)
    try:
        response = (client or urllib.request.build_opener()).open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    assert response.status == expected, f"{path}: expected {expected}, got {response.status}"
    data = response.read()
    return json.loads(data) if data and data[:1] in (b"{", b"[") else data, response.headers


configuration = json.loads(compose("config", "--format", "json").stdout)
assert set(configuration["services"]["api"]["networks"]) == {"default", "private"}
assert not configuration["services"]["api"].get("ports")
assert set(configuration["services"]["database"]["networks"]) == {"private"}
assert configuration["networks"]["private"]["internal"] is True
assert not configuration["networks"]["default"].get("internal", False)

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

# Agent access must work through the packaged web proxy, not only the API router.
assert request("/.well-known/oauth-protected-resource/mcp")[0]["resource"] == ORIGIN + "/mcp"
assert request("/.well-known/oauth-authorization-server")[0]["issuer"] == ORIGIN
assert request("/v1/agent-openapi.json")[0]["openapi"] == "3.1.0"
agent_consent = {"device_id": "COMPOSE-OWNER", "name": "Compose assistant", "scopes": ["sleep:read"], "history_days": 30, "timezone": "UTC", "expires_in_days": 7}
agent = request("/v1/agent-connections", agent_consent, client=owner)[0]
agent_key = agent["key"]
assert "key" not in request("/v1/agent-connections", client=owner)[0]["connections"][0]
assert request("/v1/agent-connections", client=member)[0]["connections"] == []
request("/v1/agent-connections/" + str(agent["connection"]["id"]), client=member, method="DELETE", expected=404)
request("/v1/agent/available_data", bearer=agent_key)
request("/v1/agent/weight_history", bearer=agent_key, expected=403)
request("/v1/admin/stats", bearer=agent_key, expected=401)
request("/v1/ingest", {}, bearer=agent_key, expected=401)
initialize = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "compose-test", "version": "1"}}}
# The MCP SDK requires the Streamable HTTP Accept header.
mcp_request = urllib.request.Request(ORIGIN + "/mcp", json.dumps(initialize).encode(), {"Content-Type": "application/json", "Accept": "application/json, text/event-stream", "Authorization": "Bearer " + agent_key})
with urllib.request.urlopen(mcp_request, timeout=20) as response:
    assert "tools" in json.load(response)["result"]["capabilities"]
revoked = request("/v1/agent-connections", agent_consent, client=owner)[0]
request("/v1/agent-connections/" + str(revoked["connection"]["id"]), client=owner, method="DELETE", expected=204)
request("/v1/agent/available_data", bearer=revoked["key"], expected=401)

compose("restart", "api", "web")
compose("up", "-d", "--wait")
assert request("/v1/setup")[0]["available"] is False
request("/v1/auth/me", client=owner)
request("/v1/agent/available_data", bearer=agent_key)

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
    # Moving a backup to another origin must not extend the old key's audience.
    request("/v1/agent/available_data", bearer=agent_key, origin=ORIGIN, expected=401)
    request("/v1/agent/available_data", bearer=revoked["key"], origin=ORIGIN, expected=401)
    restored_agent = request("/v1/agent-connections", agent_consent, client=restored, origin=ORIGIN)[0]
    request("/v1/agent/available_data", bearer=restored_agent["key"], origin=ORIGIN)
    print("PASS: setup, isolation, agent permissions/MCP/revocation, restart, backup and restore")
finally:
    compose("down", "-v", env=restore_env, check=False)
    backup.unlink(missing_ok=True)
