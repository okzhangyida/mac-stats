#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-/Users/admin/MacStats/dist/Mac Stats.app}"

open "$APP_PATH"
sleep 8
FIRST_PID="$(pgrep -x MacStats)"
[[ -n "$FIRST_PID" ]]

pkill -x MacStats
for _ in {1..20}; do
    pgrep -x MacStats >/dev/null 2>&1 || break
    sleep 0.25
done
if pgrep -x MacStats >/dev/null 2>&1; then
    echo "Mac Stats did not exit cleanly."
    exit 1
fi

open "$APP_PATH"
sleep 8
SECOND_PID="$(pgrep -x MacStats)"
[[ -n "$SECOND_PID" ]]
[[ "$FIRST_PID" != "$SECOND_PID" ]]

echo "First launch PID: $FIRST_PID"
echo "Relaunch PID: $SECOND_PID"
sw_vers
xcodebuild -version
swift --version
