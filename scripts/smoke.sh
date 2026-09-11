#!/usr/bin/env bash
# Flatpak smoke test for Gosh Calc.
#
# Installs the build-dir Flatpak (build with scripts/verify.sh or
# flatpak-builder), launches it under a display server, confirms the
# process stays alive for a fixed interval without fatal errors, and
# exits cleanly.
set -euo pipefail

APP_ID=dev.goshapps.calc
BUILD_DIR="${BUILD_DIR:-build-dir}"
REPO="${REPO:-repo}"
HOLD_SECONDS="${HOLD_SECONDS:-10}"
LOG="$(mktemp -t gosh-calc-smoke.XXXXXX.log)"
trap 'rm -f "$LOG"' EXIT

# --- install -----------------------------------------------------------------
if ! flatpak info --user "$APP_ID" >/dev/null 2>&1; then
    echo "smoke: installing $APP_ID from $BUILD_DIR"
    flatpak-builder --user --install --force-clean "$BUILD_DIR" \
        "flatpak/$APP_ID.yml" >/dev/null
fi

# --- pick a display -----------------------------------------------------------
# Prefer an existing Wayland session; fall back to a headless Weston
# instance, then to the existing X11 display if there is one.
ENV_PREFIX=()
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo "smoke: using existing Wayland display $WAYLAND_DISPLAY"
elif command -v weston >/dev/null 2>&1; then
    SOCK="gosh-calc-smoke-$$"
    echo "smoke: starting headless weston on socket $SOCK"
    weston --backend=headless --socket="$SOCK" --idle-time=0 >/dev/null 2>&1 &
    WPID=$!
    trap 'kill "$WPID" 2>/dev/null || true; rm -f "$LOG"' EXIT
    sleep 2
    ENV_PREFIX=(env "WAYLAND_DISPLAY=$SOCK" "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}")
elif [ -n "${DISPLAY:-}" ]; then
    echo "smoke: using existing X11 display $DISPLAY"
else
    echo "smoke: ERROR no display server available" >&2
    exit 1
fi

# --- launch ------------------------------------------------------------------
echo "smoke: launching $APP_ID"
"${ENV_PREFIX[@]}" flatpak run --user "$APP_ID" >"$LOG" 2>&1 &
PID=$!

alive=true
for _ in $(seq "$HOLD_SECONDS"); do
    if ! kill -0 "$PID" 2>/dev/null; then
        alive=false
        break
    fi
    sleep 1
done

if ! $alive; then
    echo "smoke: FAIL - process exited within ${HOLD_SECONDS}s" >&2
    cat "$LOG" >&2
    exit 1
fi

if grep -qiE 'panic|fatal|thread .+ panicked' "$LOG"; then
    echo "smoke: FAIL - fatal error in log" >&2
    cat "$LOG" >&2
    kill "$PID" 2>/dev/null || true
    exit 1
fi

# --- shutdown -----------------------------------------------------------------
kill "$PID" 2>/dev/null || true
for _ in $(seq 5); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 1
done
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "smoke: PASS - ran ${HOLD_SECONDS}s, no fatal errors"
cat "$LOG" | sed 's/^/smoke: app log: /'
