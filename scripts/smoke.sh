#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/smoke.py "${1:-target/debug/gosh-calc}"
