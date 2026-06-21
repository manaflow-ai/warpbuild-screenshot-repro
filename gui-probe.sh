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

echo "=== AppKit foreground activation probe (the decisive XCUITest-relevant check) ==="
swiftc -O Sources/probe/main.swift -o "${RUNNER_TEMP:-/tmp}/gui-probe"
"${RUNNER_TEMP:-/tmp}/gui-probe"
APPKIT_RC=$?
echo "appkit_probe_exit=$APPKIT_RC (0=PASS foreground GUI session, non-zero=FAIL/headless)"
exit $APPKIT_RC
