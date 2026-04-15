# warpbuild-screenshot-repro

Minimum reproduction of a screen-capture issue on WarpBuild's `warp-macos-latest-arm64-6x` macOS runners.

## Symptom

`screencapture` of an active macOS app (e.g. TextEdit) returns a PNG where:

- The menu bar renders correctly (proves the screencapture pipeline works)
- The entire desktop area below the menu bar is **solid black** (mean pixel brightness ≈ 5/255)
- The expected window content (e.g. TextEdit's "Untitled" document with toolbar/ruler) is **not visible**

This blocks any workflow that needs visual verification of macOS apps in CI: XCUITest screenshot diffs, dogfood screenshots after build, screen recording for visual regression, etc.

## Repro

`.github/workflows/repro.yml` runs two jobs side-by-side:

1. `warpbuild` — `runs-on: warp-macos-latest-arm64-6x`
2. `github-hosted-control` — `runs-on: macos-15` (GitHub-hosted)

Both:

```bash
open -a TextEdit
sleep 4
screencapture -x desktop.png
```

Then measure mean pixel brightness for the full image and the body region (excluding menu bar).

**Expected:** WarpBuild body brightness ≈ 5 (black), GitHub control body brightness > 100 (real desktop with TextEdit window visible).

## Trigger

Push to `main` or run manually:

```bash
gh workflow run repro.yml --repo manaflow-ai/warpbuild-screenshot-repro
```

Then download the screenshots artifact to compare.

## Suspected root cause

Apple's `Virtualization.framework` does not pass the host GPU through to macOS guests, so Metal/CoreAnimation has no real compositor target. Window backing stores never get rasterized.

Reference: [`cirruslabs/tart#1032`](https://github.com/cirruslabs/tart/issues/1032).

This is consistent with what we observe on:

| Provider | Result |
|---|---|
| WarpBuild `warp-macos-latest-arm64-6x` (M4 Pro Virtual) | ❌ black |
| Depot `depot-macos-latest` (M2 Pro Virtual) | ❌ black |
| GitHub `macos-15` and `macos-15-xlarge` | ✅ renders |
| Self-hosted physical Mac mini (M4) | ✅ renders |

GUI session itself is fine on WarpBuild (`launchctl print gui/$(id -u)` shows `type=login session=Aqua creator=loginwindow`, WindowServer is running). The problem is GPU-side, not session-side.

## What we'd love to know

Is GPU-accelerated macOS on WarpBuild's roadmap? The M4 Pro hardware is great otherwise.
