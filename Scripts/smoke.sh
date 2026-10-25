#!/usr/bin/env bash
# Launches build/Reclaim.app in sandbox mode inside the write sandbox, checks it stays alive
# for N seconds, then quits it. Extra arguments are passed to the app.
#
# Usage: Scripts/smoke.sh [seconds] [app args...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SECONDS_ALIVE="${1:-10}"
shift || true
BIN="$ROOT/build/Reclaim.app/Contents/MacOS/Reclaim"
[ -x "$BIN" ] || { echo "smoke: build the app first (make app-dev)" >&2; exit 1; }

LOG="$(mktemp -t reclaim-smoke)"
"$ROOT/Scripts/run-sandboxed.sh" "$BIN" --sandbox "$@" >"$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 "$SECONDS_ALIVE"); do
  sleep 1
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "smoke: FAIL - Reclaim exited early"; cat "$LOG"; exit 1
  fi
done

APP_PID="$(pgrep -f "$BIN --sandbox" | head -1 || true)"
echo "smoke: Reclaim alive after ${SECONDS_ALIVE}s (pid ${APP_PID:-$PID}, sandboxed)"
kill "$PID" 2>/dev/null || true
[ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
grep -v '^canary' "$LOG" | tail -20 || true
rm -f "$LOG"
