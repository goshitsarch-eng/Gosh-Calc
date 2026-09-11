# Architecture — Gosh Calc

## State ownership

Single source of truth: `App { core, nav_model, state: CalcState,
store: Option<Config>, toasts: Toasts<Message> }`. Engine owns all
calc semantics; `nav_model` owns mode selection UI; `Toasts` owns
transient notifications. No mirrored state: `active_mode()` derives
from nav, display strings derive from `CalcState` per-frame. No
contradictory states reachable (mode/base/angle cross-checked by
`allowed_in` gates + `set_mode`/`set_base` normalization).

## Message/update design

`Message` (19 variants) splits cleanly: engine mutations funneled
through free `reduce()` (testable without `Core`), shell concerns
(`CopyResult`, `ToggleContext`, `Surface`, `KeyPressed`,
`ToastClose`) handled in `update()`. `KeyPressed` maps through
`key_message` then re-enters `reduce` — one funnel, no duplication.
`update()` returns at most one Task per event; toast push and
clipboard write batched on copy. No async state ⇒ no
stale-result-overwrite class.

## Module boundaries

`engine` (pure) / `config` (persistence) / `i18n` (localization) /
`main` (shell+view). Engine never imports libcosmic — enforced by
review (localizing the error string happens at the view boundary,
keeping the seam clean). `config` depends on engine types only for
`HistoryEntry`/`Mode`/`AngleUnit`.

## Changes made in this audit

- Toast ownership added to `App` + `ToastClose(ToastId)` variant:
  justified (native feedback pattern), small surface.
- `needs_save()` gate centralizes the persistence policy that was
  previously "save everywhere".
- `sanitize_persisted()` gives load a validation boundary it lacked.
- Safe-char handling in `key_message`; non-panicking fmt fallback.
- No giant-module surgery: engine (1647 lines) is cohesive
  (tokenizer/evaluator/format in one pure unit with 26 tests);
  splitting it would add abstraction without correctness gain.

## Known warts (kept deliberately)

- `tests/integration.rs` mirrors the reducer instead of importing it
  (binary crate has no lib target). Extracting a lib crate would
  churn the Flatpak manifest paths; the mirror carries a "kept in
  sync" comment and covers identical method calls. Deferred, noted.
- `reduce()` ignores shell-only variants via `_` — correct by
  construction (they never reach it from `update`), and the KeyPressed
  path maps before reducing.
