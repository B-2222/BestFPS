#!/usr/bin/env bash
# Drives the two-process multiplayer check. Both sides must pass.
#
# The host is started first and given a moment to open its port; the client
# then joins on loopback. Both write to their own log, and both logs are shown
# on failure -- a multiplayer bug is usually only legible from both ends.
set -uo pipefail
GODOT="${GODOT:-godot}"
LOGS="${LOGS:-/tmp/netplay}"
mkdir -p "$LOGS"

"$GODOT" --headless --path . --script scripts/tests/net_play_test.gd -- --host \
  > "$LOGS/host.log" 2>&1 &
HOST_PID=$!
sleep 3

CODE=$(grep -m1 "^CODE " "$LOGS/host.log" | awk '{print $2}')
if [ -z "$CODE" ]; then
  echo "host never printed a join code"; cat "$LOGS/host.log"; kill $HOST_PID 2>/dev/null; exit 1
fi
echo "joining with code $CODE"

"$GODOT" --headless --path . --script scripts/tests/net_play_test.gd -- --join "$CODE" \
  > "$LOGS/client.log" 2>&1
CLIENT_STATUS=$?
wait $HOST_PID
HOST_STATUS=$?

grep -E "^    (ok|FAIL)|checks," "$LOGS/host.log" | sed 's/^/  host   /'
grep -E "^    (ok|FAIL)|checks," "$LOGS/client.log" | sed 's/^/  client /'

if [ $HOST_STATUS -ne 0 ] || [ $CLIENT_STATUS -ne 0 ]; then
  echo "net play test FAILED (host=$HOST_STATUS client=$CLIENT_STATUS)"
  echo "--- host log ---";   tail -30 "$LOGS/host.log"
  echo "--- client log ---"; tail -30 "$LOGS/client.log"
  exit 1
fi
echo "net play test PASSED"
