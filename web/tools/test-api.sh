#!/usr/bin/env bash
# Run inside the web development shell; never uses a supplied DB URL.
set -euo pipefail
web=$(cd "$(dirname "$0")/.." && pwd)
cd "$web"
ZOOP_API_DIR=${ZOOP_API_DIR:-"$web/../server"}
api=$(cd "$ZOOP_API_DIR" && pwd)
(cd "$api" && nix develop --command cargo build --locked -p zoop)
binary="$api/target/debug/zoop"
fixture_dir=$(mktemp -d)
chmod 700 "$fixture_dir"
api_pid=""
cleanup() {
  if [ -n "$api_pid" ]; then kill "$api_pid" 2>/dev/null || true; wait "$api_pid" 2>/dev/null || true; fi
  pg_ctl -D "$fixture_dir/pg" stop -m fast >/dev/null 2>&1 || true
  rm -rf "$fixture_dir"
}
trap cleanup EXIT
initdb -D "$fixture_dir/pg" -U zoop --auth=trust --no-locale >/dev/null
# Private Unix socket only: this database is never reachable over TCP.
pg_ctl -D "$fixture_dir/pg" -o "-h '' -k $fixture_dir -p 19440" -l "$fixture_dir/pg.log" start >/dev/null
createdb -h "$fixture_dir" -p 19440 -U zoop zoop_test
cat > "$fixture_dir/config.toml" <<EOF
[server]
bind="127.0.0.1:18471"
ingest_token="dev-integration-only"
[storage]
postgres_url="postgres://zoop@localhost/zoop_test?host=$fixture_dir&port=19440"
[web]
enabled=true
origin="http://127.0.0.1:5173"
[worker]
history_enabled=false
EOF
export ZOOP_E2E_PASSWORD='synthetic-only integration password'
printf '%s' "$ZOOP_E2E_PASSWORD" > "$fixture_dir/password"
chmod 600 "$fixture_dir/password"
"$binary" migrate --config "$fixture_dir/config.toml" >/dev/null
"$binary" account create --config "$fixture_dir/config.toml" --email admin@example.test --password-file "$fixture_dir/password" --admin >/dev/null
"$binary" account create --config "$fixture_dir/config.toml" --email member@example.test --password-file "$fixture_dir/password" >/dev/null
"$binary" account bind-device --config "$fixture_dir/config.toml" --email admin@example.test --device DEMO-A >/dev/null
"$binary" account bind-device --config "$fixture_dir/config.toml" --email member@example.test --device DEMO-B >/dev/null
psql -h "$fixture_dir" -p 19440 -U zoop -d zoop_test -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
INSERT INTO devices(id,model) VALUES('DEMO-A','TEST'),('DEMO-B','TEST');
INSERT INTO weight_readings(device_id,id,measured_at,kg,source,source_name)
VALUES('DEMO-A','synthetic-a',now(),64.2,'snoop','Synthetic'),('DEMO-B','synthetic-b',now(),89.7,'snoop','Synthetic');
SQL
"$binary" run --config "$fixture_dir/config.toml" > "$fixture_dir/api.log" 2>&1 &
api_pid=$!
for attempt in {1..100}; do
  kill -0 "$api_pid" || { cat "$fixture_dir/api.log"; exit 1; }
  if curl -fsS http://127.0.0.1:18471/health >/dev/null; then break; fi
  sleep 0.1
done
export ZOOP_E2E_REAL=1 ZOOP_API_URL=http://127.0.0.1:18471
export CHROMIUM_PATH=${CHROMIUM_PATH:-$(command -v chromium)}
npm run test:e2e -- tests/browser/live.spec.ts
