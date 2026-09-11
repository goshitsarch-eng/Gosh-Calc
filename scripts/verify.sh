#!/usr/bin/env bash
# One-command verification for Gosh Calc:
#   fmt -> clippy -> tests -> flatpak build -> smoke test
# Exits nonzero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n== %s ==\n' "$*"; }

step "cargo fmt --check"
if command -v rustfmt >/dev/null 2>&1; then
    cargo fmt --check
else
    echo "verify: rustfmt not available, skipping"
fi

step "cargo clippy --all-targets -- -D warnings"
cargo clippy --all-targets -- -D warnings

step "cargo test"
cargo test

if command -v flatpak-builder >/dev/null 2>&1; then
    step "flatpak-builder"
    flatpak-builder --force-clean --user --install-deps-from=flathub \
        build-dir flatpak/dev.goshapps.calc.yml

    step "smoke test"
    scripts/smoke.sh
else
    echo "verify: flatpak-builder not available, skipping flatpak build + smoke"
fi

echo
echo "verify: all checks passed"
