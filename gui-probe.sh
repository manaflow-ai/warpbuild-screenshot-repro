#!/usr/bin/env bash
# Combined macOS GUI-session probe. Run on multiple runner labels (Blacksmith,
# Warp, GitHub-hosted) to compare. Two independent checks:
#   1. screencapture brightness  -> is there a rendered Aqua desktop at all?
#   2. AppKit foreground activation (Sources/probe/main.swift) -> can a GUI app
#      become active/key? This is the exact condition our XCUITest/unit suite
#      needs (apps stuck "Running Background" fail ~100 tests).
#
# The AppKit probe runs LAST and its exit code becomes the job's exit code, so
# a red job == "no foreground GUI session" (the blocker). screencapture output
# is uploaded regardless via the workflow's if: always() artifact step.
set -uo pipefail

echo "=== runner ==="
echo "RUNNER_NAME=${RUNNER_NAME:-?}"
echo "console_user=$(stat -f %Su /dev/console)   (root => nobody logged into Aqua)"

echo "=== sysctl ==="
sysctl -n hw.model hw.ncpu hw.memsize machdep.cpu.brand_string 2>/dev/null || true

echo "=== sw_vers ==="
sw_vers

echo "=== gui session (launchctl gui/uid) ==="
launchctl print "gui/$(id -u)" 2>&1 | head -8 || echo "no gui session"

echo "=== WindowServer / loginwindow ==="
ps -axo pid,user,comm | grep -iE '[W]indowServer|[l]oginwindow' || echo "  (none running)"

echo "=== automationmodetool (documented headless XCTest unblock) ==="
sudo -n automationmodetool enable-automationmode-without-authentication 2>&1 | head -3 \
  || echo "  (sudo/automationmodetool unavailable)"

echo "=== screencapture probe ==="
mkdir -p /tmp/probe
open -a TextEdit 2>&1 || echo "open TextEdit failed"
sleep 4
pgrep -fl TextEdit || echo "TextEdit didn't start"
screencapture -x /tmp/probe/desktop.png 2>&1 || echo "screencapture failed"
ls -la /tmp/probe/desktop.png 2>&1 || true
if [ -f /tmp/probe/desktop.png ]; then
  python3 -m pip install --quiet --break-system-packages Pillow 2>&1 | tail -1 || true
  python3 - <<'PY' || true
from PIL import Image
im = Image.open('/tmp/probe/desktop.png')
px = list(im.getdata())
mean = sum(sum(p[:3]) for p in px) / (len(px) * 3)
print(f'screencapture mean brightness: {mean:.2f}/255 (0=black, >20 => real desktop rendered)')
print(f'image size: {im.size}')
PY
fi

echo "=== AppKit foreground activation probe — BARE (no virtual display) ==="
swiftc -O Sources/probe/main.swift -o "${RUNNER_TEMP:-/tmp}/gui-probe"
"${RUNNER_TEMP:-/tmp}/gui-probe"
BARE_RC=$?
echo "appkit_bare_exit=$BARE_RC"

# ---------------------------------------------------------------------------
# Decisive stage: replicate what the REAL cmux display jobs do. They create a
# CGVirtualDisplay first (scripts/create-virtual-display.m) and only then run
# XCUITest. Warp passes the real jobs despite failing the BARE probe precisely
# because of this step, so the virtual-display retry is the fair predictor of
# whether our CI jobs can run on a given runner.
# ---------------------------------------------------------------------------
echo "=== create CGVirtualDisplay (mirror of ci.yml 'Create virtual display') ==="
HELPER="${RUNNER_TEMP:-/tmp}/cvd"
READY="${RUNNER_TEMP:-/tmp}/cvd.ready"
IDP="${RUNNER_TEMP:-/tmp}/cvd.id"
LOG="${RUNNER_TEMP:-/tmp}/cvd.log"
rm -f "$READY" "$IDP" "$LOG"
clang -framework Foundation -framework CoreGraphics -o "$HELPER" create-virtual-display.m \
  && echo "cvd helper built" || echo "cvd helper build FAILED"
"$HELPER" --ready-path "$READY" --display-id-path "$IDP" >"$LOG" 2>&1 &
CVD_PID=$!
for _ in $(seq 1 100); do
  { [ -s "$READY" ] && [ -s "$IDP" ]; } && break
  kill -0 "$CVD_PID" 2>/dev/null || { echo "cvd helper exited early"; break; }
  sleep 0.1
done
echo "--- cvd helper log ---"; cat "$LOG" 2>/dev/null || true
if [ -s "$IDP" ]; then
  echo "virtual_display_created=yes id=$(tr -d '\n' < "$IDP")"
else
  echo "virtual_display_created=no (CGVirtualDisplay could not be created on this runner)"
fi

echo "=== AppKit foreground activation probe — WITH virtual display ==="
"${RUNNER_TEMP:-/tmp}/gui-probe"
VD_RC=$?
echo "appkit_with_vdisplay_exit=$VD_RC"
kill "$CVD_PID" >/dev/null 2>&1 || true

echo "=== VERDICT ==="
echo "bare_activation_pass=$([ $BARE_RC -eq 0 ] && echo yes || echo no)"
echo "vdisplay_created=$([ -s "$IDP" ] && echo yes || echo no)"
echo "activation_with_vdisplay_pass=$([ $VD_RC -eq 0 ] && echo yes || echo no)"
# Job is GREEN only if the runner can run our real flow: activation works after
# a virtual display is created (the bare check is informational).
exit $VD_RC
