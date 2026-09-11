# Baseline — Gosh Calc audit (branch `audit-hardening`, parent `e05abe4`)

Recorded before any fix. All observations verified by reading source,
running the suite, and running validators in this checkout.

## Repository structure

Binary-only crate (no lib target):

- `src/main.rs` (683 lines) — libcosmic shell: `App`, `Message`,
  `reduce()`, `key_message()`, `view()` + keypad builders
- `src/engine.rs` (1647 lines) — pure-Rust calc engine, no libcosmic
  imports; 26 unit tests inline
- `src/config.rs` (58 lines) — cosmic-config file-backend persistence
- `src/i18n.rs` (42 lines) — i18n-embed + Fluent loader, `fl!` macro
- `tests/integration.rs` (220 lines) — 7 flow tests via `#[path]`
  include of `src/engine.rs` plus a locally mirrored reducer
- `i18n/en/gosh_calc.ftl` — 12 keys
- `resources/` — desktop entry, AppStream metainfo, hicolor SVG icon
- `flatpak/` — manifest, `cargo-sources.json`, generator script
- `scripts/` — `verify.sh`, `smoke.sh`
- `docs/design/` — architecture, ux, packaging, PLAN, DECISIONS

## Architecture summary

Immediate-execution calculator. `CalcState` holds a committed token
list (`expr`), a raw in-progress operand string (`entry`), error slot,
repeat-equals slot, and history (cap 100). `=` evaluates with
precedence climbing. `Value = F(f64) | I(i64)` — float domain for
standard/scientific, exact i64 for programmer. `main.rs` translates
`Message` into engine calls through a free `reduce()` function;
`update()` handles clipboard/context/surface/keyboard around it.
Persistence via `cosmic-config` file backend (no dbus-config):
mode, angle, history. Nav bar switches the three modes.

## Supported features (observed in code)

Standard / scientific / programmer keypads, expression + result
display, four-base readout, history context drawer with recall/clear,
copy-result button + Ctrl+C, full keyboard map incl. numpad,
DEG/RAD toggle, percent (GNOME semantics), repeat-equals,
parens with auto-close, persistence of mode/angle/history.

## Build process

`cargo build` — pinned libcosmic git rev `b7288527` (644-crate tree,
vendored in lockfile). Release profile: thin LTO, opt 3.

## Packaging process

`flatpak/dev.goshapps.calc.yml` — Freedesktop runtime/SDK 25.08,
rust-stable extension, offline cargo vendor build. Verified:
`flatpak-builder --show-manifest` expands `cargo-sources.json`
correctly (vendored-sources config emitted inline). finish-args:
wayland + fallback-x11 + ipc + dri only. No network/filesystem/bus.

## Test coverage (baseline)

`cargo test`: 33 passed (26 engine unit + 7 integration), 0 failed.
Covers arithmetic, precedence, float artifacts, chained/repeat-equals,
percent, unary minus, backspace/clear, div-by-zero recovery, scientific
functions, trig DEG/RAD, parens, constants/overflow, factorial domain,
programmer bases/bitwise/int-division, readout, history, mode-switch
conversion, base filtering, fmt edge cases, huge-operand and
state-churn fuzz checks.

## Current warnings / failures

- `cargo fmt --check`: FAILS — diffs in `src/config.rs` (import order)
  and `src/engine.rs` (long match formatting). Baseline failure #1.
- `cargo clippy --all-targets -- -D warnings`: passes.
- `cargo test`: passes (33/33).
- `desktop-file-validate`: passes with 1 hint (multiple main
  categories `Utility;Science;Math;` — cosmetic only).
- `appstreamcli validate --pedantic`: passes with 1 info
  (`developer-id-missing` — informational, no reversed-DNS
  requirement for this component).
- Flatpak: `build-dir/` + `.flatpak-builder/` from a prior successful
  build exist in-tree; app installed as
  `app/dev.goshapps.calc/x86_64/master`. Fresh `--force-clean`
  rebuild not yet run on this branch.
- No README at repo root (docs live in `docs/design/`).

## Known/documented features (docs/design)

PLAN checklist, ux spec (window/nav/display/keypads/history/keyboard/
copy/persistence/a11y/i18n), architecture doc, DECISIONS D1–D11,
packaging doc. See FEATURES.md matrix for trace results.

## Visible UI features

Header bar (title + history toggle), nav bar (3 modes), display area
(expression line, result line, copy button, base readout + base
selector in programmer, DEG/RAD caption in scientific), keypads
(standard 6x4, scientific 6x8, programmer 6x6), history context drawer
(list + clear footer).

## Obvious incomplete functionality (pre-fix notes)

1. `cargo fmt` red (see above).
2. Copy gives no user feedback (`copied` ftl key dead).
3. Error line hardcodes English "Error" (`error` ftl key dead).
4. History header icon is a sort-ascending glyph, not history/clock.
5. Clear-history button active with empty history.
6. Keyboard gaps vs ux spec: no Ctrl+Insert copy, no plain `h`
   history toggle (code wants Ctrl+H).
7. Config (mode+angle+100-entry history incl. full serialize) written
   on EVERY keystroke.
8. Loaded history/entry unbounded (no truncation of hostile config).
9. `unwrap()` on keyboard-derived char (`main.rs:169`).
10. README missing; ux sketches disagree with shipped grids.

## Baseline runtime observations

GUI not launched headless during recon (no display assertion made);
engine behavior verified through the 33-test suite. Flatpak smoke
(`scripts/smoke.sh`, weston present) deferred to verification pass.
