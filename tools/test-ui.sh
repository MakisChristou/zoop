#!/bin/bash
# Synthetic smoke tests. Never connects to a strap or a personal server.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
PYTHONDONTWRITEBYTECODE=1 python3 tools/layout-test-server.py > /tmp/zoop-ui-fixture.log 2>&1 &
fixture_pid=$!
PYTHONDONTWRITEBYTECODE=1 python3 tools/goal-history-test-server.py > /tmp/zoop-goal-fixture.log 2>&1 &
goal_pid=$!
trap 'kill "$fixture_pid" "$goal_pid" 2>/dev/null || true' EXIT
ready=false
for attempt in {1..50}; do
  kill -0 "$fixture_pid" "$goal_pid" || { cat /tmp/zoop-ui-fixture.log /tmp/zoop-goal-fixture.log; exit 1; }
  if curl -fsS http://127.0.0.1:28476/health >/dev/null 2>&1 && curl -fsS http://127.0.0.1:28483/health >/dev/null 2>&1; then ready=true; break; fi
  sleep 0.1
done
$ready || { echo "Fixture server did not start"; exit 1; }
device=${ZOOP_SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"].startswith("iPhone")))')}
xcodebuild -scheme Zoop -destination "platform=iOS Simulator,id=$device" \
  ${ZOOP_DERIVED_DATA:+-derivedDataPath "$ZOOP_DERIVED_DATA"} \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -parallel-testing-enabled NO \
  -only-testing:ZoopUITests/LoadingFeedbackTests \
  -only-testing:ZoopUITests/ActivityTimelineTests \
  -only-testing:ZoopUITests/SignInTests \
  -only-testing:ZoopUITests/SetupUITests \
  -only-testing:ZoopUITests/GoalHistoryUITests \
  -only-testing:ZoopUITests/HealthWeightTests test
