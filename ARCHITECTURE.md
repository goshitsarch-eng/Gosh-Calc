# Architecture

Gosh Calc 0.3 is a Godot 4.7 project written entirely in GDScript. One
renderer-agnostic UI runs on Windows, macOS and Linux with the GL Compatibility
renderer. No Electron, Flutter, WebView, Rust toolchain, Node runtime or
external process is involved.

## Layers (`core/` has no UI or platform dependency)

* `core/num.gd`, `core/big.gd`: exact decimal ⇄ binary64 conversion (parsing is
  correctly rounded; formatting rounds the exact value half-to-even). Godot's
  built-in `to_float`/printf are not correctly rounded and are not used for
  calculator values.
* `core/engine.gd` (`GcEngine`): the token/entry calculator. GDScript `int` is
  an exact `i64` (programmer mode) and `float` an IEEE double. Checked integer
  arithmetic is written out explicitly. `log10` and `cbrt` are derived from
  `log`/`pow` (GDScript has neither) with exact-power/perfect-cube snapping.
* `core/commands.gd`, `core/app_state.gd`: one command reducer used by keypad,
  keyboard, menus and history; availability rules; effect flags (persist, copy,
  quit); the DOM-style keyboard map.
* `core/store.gd`, `core/json.gd`, `core/ron.gd`, `core/writer.gd`: versioned
  `settings.json` (strict, serde-compatible JSON that keeps int64 exact), bounded
  reads, atomic replace, corrupt-file backup, read-only legacy RON import, and a
  background writer thread that coalesces bursts and flushes on exit.
* `core/app_info.gd`: identity, version, platform keyboard policy, CLI.
* `ui/`: `main.gd` (shell: window/HiDPI, menus, theme, clipboard, persistence),
  `palette.gd` (design tokens → one `Theme`; swapping it restyles the app),
  display/keypad/history/dialog views, and small widgets (`key_grid`,
  `scroll_text`, `button`, `icons`). Views emit commands; they hold no calculator
  state and do no arithmetic or file I/O.

## Runtime and data

No network, file dialogs, printing or external commands. History is rendered as
text. Writes occur only on durable changes (mode, angle, theme, history, window
geometry) and run off the UI thread. Fonts (Inter, DejaVu) are bundled so glyph
coverage and metrics do not depend on the OS. The window is sized in logical
pixels and scaled by the screen scale factor, so the saved size is
DPI-independent.

## Validation (`tests/`)

* `unit/`: ports of every Rust engine/integration/migration test plus numeric,
  JSON, RON and settings-compatibility tests.
* `golden/`, `fixtures/`: data recorded from the Rust release (see
  `tests/tools/golden/README.md`); replayed by `unit/test_golden.gd`.
* `ui/ui_checks.gd`: end-to-end checks of the real scene via synthesized mouse
  and keyboard events (needs a display; `xvfb-run` works).
* `diff_runner.gd`: replays any recorded corpus.
