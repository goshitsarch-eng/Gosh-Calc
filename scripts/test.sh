#!/usr/bin/env bash
# Runs the whole test suite. Usage: scripts/test.sh [--core]
#   --core   only the display-free tests (unit, golden corpus, compatibility)
# UI checks need a display; without one (and without xvfb-run) they are NOT run
# and the script fails, so a green result never hides skipped UI coverage.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CORE_ONLY=0
[ "${1:-}" = "--core" ] && CORE_ONLY=1

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
echo "== unit, golden-corpus and settings-compatibility tests"
"$GODOT" --headless --path . -s tests/run_all.gd

[ "$CORE_ONLY" = 1 ] && { echo "core tests passed (UI checks skipped by request)"; exit 0; }

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  RUNNER=()
elif command -v xvfb-run > /dev/null; then
  RUNNER=(xvfb-run -a -s "-screen 0 1800x1400x24")
else
  echo "error: UI checks need a display or xvfb-run (use --core to skip them)" >&2
  exit 2
fi
for scale in 1 2; do
  echo "== UI checks at ${scale}00% scale"
  GOSH_CALC_SCALE="$scale" "${RUNNER[@]}" "$GODOT" --path . --rendering-driver opengl3 \
    --audio-driver Dummy -s tests/ui/ui_checks.gd
done
echo "all tests passed"
