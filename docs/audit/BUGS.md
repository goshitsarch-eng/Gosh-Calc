# Bugs — Gosh Calc

Confirmed by code reading + test/validator runs. Severity per PLAN
scale. All fixed unless marked otherwise.

## B1 — `cargo fmt --check` fails (P2, fixed)

`src/config.rs` import order, `src/engine.rs` match-arm layout.
Fix: `cargo fmt`. Verified with `cargo fmt --check`.

## B2 — copy has no user feedback (P2, fixed)

`CopyResult` wrote the clipboard and returned; `copied` ftl key dead.
Fix: libcosmic toaster (`widget::toaster`) + `Toast`/timeout +
`ToastClose` message; toast text uses `fl!("copied")`.
View wraps root in `toaster()`. Tests: reducer-level copy is a Task
(UI-layer), covered by toast-queue unit test on push/remove.

## B3 — error line not localized (P2, fixed)

`result_display()`/`fmt_f64()` hardcoded `"Error"`; `error` ftl key
dead. Engine must stay libcosmic-free, so localization happens at the
view boundary: `display()` shows `fl!("error")` when
`state.error.is_some()`. Engine keeps `"Error"` for logs/tests.

## B4 — wrong history icon (P2, fixed)

Header toggle used `view-sort-ascending-symbolic` (a sort glyph).
ux.md specifies a clock/history glyph. Fix:
`document-open-recent-symbolic` (freedesktop standard, guaranteed
present). Verified by icon-name review + manual launch.

## B5 — clear-history enabled when empty (P3, fixed)

Footer destructive button always armed. Fix: `on_press_maybe` with
`None` when `history.is_empty()` (button renders disabled).

## B6 — keyboard gaps vs ux contract (P2, fixed)

Spec: Ctrl+C / Ctrl+Insert copy; plain `h` toggles history.
Code: only Ctrl+C and Ctrl+H. Fix: add Ctrl+Insert copy mapping and
plain `h`/`H` (no modifiers) → `ToggleContext`. `h` is never a hex
digit so no programmer-mode conflict. Regression test added on
`key_message`.

## B7 — config written on every keystroke (P2, fixed)

`update()` called `save()` after every `reduce`, serializing up to
100 history entries per digit press. Fix: save only when persisted
state can change — `Equals`, `ClearHistory`, `ToggleAngle`,
nav-select (mode). Verified by new test asserting save-gating
predicate per message.

## B8 — hostile config can inject unbounded strings (P2, fixed)

`config::load` assigned `history` verbatim; `recall_history` and
`input_ans` cloned results into `entry` unbounded. Fix:
`CalcState::sanitize_persisted()` truncates history to MAX_HISTORY
and each expr/result to 256 chars; recall/ans clamp entry to
MAX_ENTRY_LEN. Called from `config::load`. Tests added.

## B9 — `unwrap()` on keyboard-derived char (P2, fixed)

`main.rs:169` `c.to_ascii_lowercase().chars().next().unwrap()`.
Category C (external input). Fix: safe `and_then` chain returning
`None` on empty. Tests added.

## B10 — defensive unwraps in fmt/op-correction (P3, fixed)

`engine.rs:518` (`last_mut().unwrap`, guarded but ugly),
`fmt_f64` `split_once/parse .unwrap()` (format invariant). Category
A, but converted to `if-let`/fallback returning "Error" so no panic
path exists even if the invariant ever breaks. Covered by
`fmt_f64_cases`.

## B11 — ux sketches disagree with shipped grids (P3, fixed)

ux.md drew 6x6/5-row sketches; code ships standard 6x4, scientific
6x8, programmer 6x6 with an extra standard unary row. Code is truth
(tests + pads); fix updates ux.md sketches + notes.

## B12 — no README at root (P3, fixed)

Docs lived only in `docs/design/`. Added root `README.md` (build,
run, shortcuts, Flatpak, features) consistent with metainfo.

## B13 — bare `=` spammed history (P3, fixed, red-team find)

Pressing `=` on an empty calculator appended a no-op record every
press. Fix: `equals()` updates display state but returns `None`
without recording when nothing is committed and no repeat applied.
Test: `bare_equals_records_no_history`.

## Non-bugs (investigated, legitimate)

- `i18n.rs` `.expect()` on embedded fallback load: build-time asset
  via RustEmbed; failure means broken build → category A. Kept.
- Test-only `panic!("bad test key")`, test `unwrap()`s: test code,
  fine.
- Base (HEX/DEC/…) not persisted across launches: matches
  docs/design contract (mode/angle/history only). Noted, not changed.
- Expression line blank after `=`: matches ux spec (line 1 shows the
  in-progress expression; result line shows the value; history keeps
  the record). Not changed.
- Backspace on evaluated result is a no-op (must use CE/C): GNOME
  convention, tested implicitly. Not changed.
- `single-instance`/memory keys absent: explicitly deferred in D8.
