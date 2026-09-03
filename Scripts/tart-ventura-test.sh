#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VM_NAME="${MAC_STATS_VM_NAME:-mac-stats-ventura}"
if [[ -n "${TART_BIN:-}" ]]; then
    TART_BIN="$TART_BIN"
elif command -v tart >/dev/null 2>&1; then
    TART_BIN="$(command -v tart)"
else
    TART_BIN="/Applications/Tart.app/Contents/MacOS/tart"
fi
REPORT_DIR="$PROJECT_DIR/TestReports/ventura"
REMOTE_DIR="/Users/admin/MacStats"
SHARED_DIR="/Volumes/My Shared Files/MacStats"

mkdir -p "$REPORT_DIR"

if ! "$TART_BIN" list --source local --quiet | grep -qx "$VM_NAME"; then
    echo "Tart VM '$VM_NAME' does not exist. Create it before running this script."
    exit 2
fi

function stop_vm {
    "$TART_BIN" stop "$VM_NAME" >/dev/null 2>&1 || true
}
trap stop_vm EXIT INT TERM

"$TART_BIN" run --no-graphics --dir="MacStats:$PROJECT_DIR" "$VM_NAME" &

for _ in {1..90}; do
    "$TART_BIN" exec "$VM_NAME" /usr/bin/true >/dev/null 2>&1 && break
    sleep 2
done
"$TART_BIN" exec "$VM_NAME" /usr/bin/true >/dev/null 2>&1 || {
    echo "Tart Guest Agent did not become ready."
    exit 3
}

"$TART_BIN" exec "$VM_NAME" /usr/bin/rsync -a --delete \
    --exclude .build \
    --exclude dist \
    --exclude TestReports \
    --exclude .git \
    "$SHARED_DIR/" "$REMOTE_DIR/"

set +e
"$TART_BIN" exec "$VM_NAME" /bin/zsh -lc \
    "cd '$REMOTE_DIR' && MAC_STATS_SNAPSHOT_DIR='$SHARED_DIR/TestReports/ventura' ./Scripts/check-macos13.sh" \
    2>&1 | tee "$REPORT_DIR/build-and-test.log"
TEST_STATUS=${pipestatus[1]}
set -e

"$TART_BIN" exec "$VM_NAME" /bin/zsh -lc \
    "cd '$REMOTE_DIR' && ./Scripts/build-app.sh debug"
"$TART_BIN" exec "$VM_NAME" /bin/zsh -lc \
    "'$REMOTE_DIR/Scripts/vm-app-smoke-test.sh' '$REMOTE_DIR/dist/Mac Stats.app'" \
    > "$REPORT_DIR/smoke-test.txt"

exit "$TEST_STATUS"
