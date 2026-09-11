# Packaging, platform & QA — Gosh Calc

## Cargo

Pinned libcosmic git rev `b7288527` + full Cargo.lock; feature set
minimal (`winit, tokio, a11y, x11, wayland, wgpu, xdg-portal`;
`default-features = false`; dbus-config off per D2 so the app runs
without COSMIC session services). Release: thin LTO + opt 3.
No unused/duplicate deps found; no upgrades performed (no
security/correctness driver — policy: don't churn pinned GUI rev).

## Desktop / metainfo / icons

- `resources/dev.goshapps.calc.desktop`: `desktop-file-validate`
  passes (one hint: multiple main Categories — cosmetic, kept since
  Utility+Science both apply; single-main-category rule is advisory).
- `resources/dev.goshapps.calc.metainfo.xml`:
  `appstreamcli validate --pedantic` passes (one info:
  developer-id-missing — informational only).
- Icon: single hicolor scalable SVG, valid XML, installed by manifest
  to the correct path. No PNG sizes needed for a symbolic-style SVG.

## Flatpak manifest

`flatpak-builder --show-manifest` confirms `cargo-sources.json`
expands to the full vendored source set (offline build,
vendored-sources config emitted inline, `cp cargo/config` path
valid). finish-args minimal: wayland, fallback-x11, ipc, dri.
No network/home/bus. Prior `build-dir` artifacts + installed
`app/dev.goshapps.calc/x86_64/master` present; full `--force-clean`
rebuild + smoke run in the verification pass. weston available for
headless smoke.

## Platform behavior

No COSMIC-service assumption: config via file backend, theme via
settings portal. Runs on plain Wayland (fallback-x11 granted for
X11 sessions). Clipboard via iced write (needs no extra sandbox
right on Wayland).

## Tests / scripts

- `cargo test`: 33/33 baseline; audit adds regression tests
  (keyboard map, save gating, sanitize/recall clamps, toast queue).
- `scripts/verify.sh`: runs fmt → clippy → test → flatpak build →
  smoke, nonzero on failure, explicit skip messages. Extended in this
  audit with desktop-file + metainfo validation gates.
- `scripts/smoke.sh`: install → launch under Wayland/weston/X11 →
  fixed-interval liveness → panic-scan → clean kill. Unchanged
  behavior; verified runnable here (weston present).
