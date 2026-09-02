#!/usr/bin/env bash
# Capture one deterministic, metadata-sanitized screenshot for the two
# comparison runners. The workflow supplies no write-capable credentials.
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PROBE_OUTPUT_DIR:-}" ]]; then
  OUTPUT_DIR="$PROBE_OUTPUT_DIR"
else
  OUTPUT_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/cmux-screenshot-probe.XXXXXX")"
fi
readonly OUTPUT_DIR
readonly OUTPUT_FILE="$OUTPUT_DIR/desktop.png"

umask 077
if [[ -L "$OUTPUT_DIR" || ( -e "$OUTPUT_DIR" && ! -d "$OUTPUT_DIR" ) ]]; then
  echo "Refusing to use a non-directory output path: $OUTPUT_DIR" >&2
  exit 1
fi
mkdir -p -m 700 "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
if [[ -L "$OUTPUT_FILE" ]]; then
  echo "Refusing to overwrite a symlink: $OUTPUT_FILE" >&2
  exit 1
fi
rm -f -- "$OUTPUT_FILE"

echo "=== sysctl (non-sensitive hardware fields) ==="
sysctl -n hw.model hw.ncpu hw.memsize machdep.cpu.brand_string

echo "=== sw_vers ==="
sw_vers

echo "=== gui session ==="
if session_info=$(launchctl print "gui/$(id -u)" 2>/dev/null); then
  printf '%s\n' "$session_info" \
    | sed -n '/type=\|session=\|creator=/p' \
    | sed -n '1,8p'
else
  echo "no gui session"
fi

echo "=== WindowServer ==="
pgrep -l WindowServer || echo "no WindowServer process"

echo "=== display ==="
# Restrict output to capability fields. Display serial numbers and EDID blobs
# are intentionally excluded from public CI logs.
/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null \
  | sed -n '/Chipset Model\|Metal Support\|Resolution\|Connection Type/p' \
  | sed -E 's/[[:space:]]+/ /g' \
  | sed -n '1,12p' || true

echo "=== screencapture probe ==="
open -a TextEdit
for _ in {1..20}; do
  if pgrep -x TextEdit >/dev/null; then
    break
  fi
  sleep 1
done
pgrep -fl TextEdit || echo "TextEdit did not start"
# TextEdit can need a short compositor interval after launch. This is a
# diagnostic wait, not a synchronization contract for application code.
sleep 2
screencapture -x "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"
ls -l "$OUTPUT_FILE"

VENV_DIR="$(mktemp -d "${TMPDIR:-/tmp}/warpbuild-probe.XXXXXX")"
cleanup() {
  rm -rf -- "$VENV_DIR"
}
trap cleanup EXIT
python3 -m venv "$VENV_DIR"
PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INPUT=1 \
  "$VENV_DIR/bin/python" -m pip install \
    --no-deps --only-binary=:all: --require-hashes \
    --index-url https://pypi.org/simple \
    -r "$SCRIPT_DIR/requirements.txt"

"$VENV_DIR/bin/python" "$SCRIPT_DIR/scripts/sanitize_png.py" "$OUTPUT_FILE"
"$VENV_DIR/bin/python" - "$OUTPUT_FILE" <<'PY'
import sys
from pathlib import Path

from PIL import Image

path = Path(sys.argv[1])
with Image.open(path) as image:
    image.load()
    pixels = list(image.convert("RGB").getdata())
    mean = sum(sum(pixel) for pixel in pixels) / (len(pixels) * 3)
    print(f"Mean pixel brightness: {mean:.2f}/255 (0=pure black, 255=white)")
    print(f"Image size: {image.size}")
    width, height = image.size
    body = image.crop((0, min(30, height), width, height)).convert("RGB")
    body_pixels = list(body.getdata())
    body_mean = sum(sum(pixel) for pixel in body_pixels) / (len(body_pixels) * 3)
    print(f"Body region (excluding menu bar) mean brightness: {body_mean:.2f}/255")
PY

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'output_file=%s\n' "$OUTPUT_FILE" >> "$GITHUB_OUTPUT"
fi
