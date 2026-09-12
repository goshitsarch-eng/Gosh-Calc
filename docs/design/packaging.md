# Gosh-Calc Packaging & QA

Owner: packaging & QA teammate. Covers the Flatpak, tests, scripts.

## Flatpak

Manifest: `flatpak/dev.goshapps.calc.yml`

- runtime: `org.freedesktop.Platform` // 25.08 (installed locally)
- sdk: `org.freedesktop.Sdk` // 25.08
- sdk-extensions: `org.freedesktop.Sdk.Extension.rust-stable`
- build-args: `CARGO_HOME` pointing at vendored sources; cargo built
  fully offline inside the sandbox.
- sources: the app tree + `cargo-sources.json`, generated from
  `Cargo.lock` by `flatpak-cargo-generator.py`
  (flatpak-builder-tools). Regenerate whenever Cargo.lock changes:
  `python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json`
- finish-args (minimal):
  - `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc` —
    windowing
  - `--device=dri` — GPU rendering; wgpu falls back to llvmpipe if
    absent, but dri is the standard grant
  - no network, no filesystem, no session-bus names: the app needs
    none. Config persists via the file backend under the app's own
    XDG config dir inside the sandbox.
- Installed artifacts: `/app/bin/gosh-calc`, desktop file, metainfo,
  SVG icon (`resources/icons/hicolor/scalable/apps/dev.goshapps.calc.svg`
  — the source of truth for the icon).

Files:

- `flatpak/dev.goshapps.calc.yml` — manifest
- `flatpak/cargo-sources.json` — vendored cargo deps (generated)
- `resources/dev.goshapps.calc.desktop` — desktop entry
- `resources/dev.goshapps.calc.metainfo.xml` — AppStream metainfo
- `resources/icons/hicolor/scalable/apps/dev.goshapps.calc.svg` — icon

## Portals / sandboxing notes

`xdg-portal` feature is enabled so theme/accent follows the host
desktop's settings portal on non-COSMIC sessions. No portal calls are
required for core function — nothing in the app touches files outside
its own XDG dirs.

## Test suite

- `src/engine.rs` unit tests (`cargo test`): every operation in every
  mode, precedence, parens, percent contexts, repeat-equals, base
  conversion, bitwise ops, error paths, `fmt_f64` edge cases, plus
  robustness tests (huge operands, hostile persisted history,
  500-step state churn).
- `tests/integration.rs`: drives full user flows through the same
  engine calls the UI uses — typed digits -> evaluate -> history ->
  recall -> mode switch -> base switch — asserting on `CalcState`,
  not pixels.
- `scripts/smoke.sh`: installs the already-built Flatpak, then
  launches it headless (existing Wayland session, else a headless
  weston instance, else the existing X11 display), checks it stays
  alive for ~10 s with no panic/fatal in the log, then kills it.

## scripts/verify.sh

Runs, in order:

1. `cargo fmt --check` (if rustfmt present)
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test`
4. `desktop-file-validate` and `appstreamcli validate` (each skipped
   with a warning when unavailable)
5. `flatpak-builder --force-clean` build (skipped with a warning when
   flatpak-builder or the SDK is unavailable)
6. `scripts/smoke.sh` (same availability gate)

`verify.sh` exits nonzero on any failure; warnings are printed for
skipped stages so CI vs. local runs are distinguishable.
