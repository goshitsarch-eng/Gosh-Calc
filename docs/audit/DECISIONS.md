# Audit decisions (appended to docs/design/DECISIONS.md D1–D11)

## D12: toast for copy feedback, not silent clipboard write

Copy worked but gave no feedback while a `copied` string sat dead.
Chose libcosmic `widget::toaster` (`Toasts` in `App`, `ToastClose`
message, timeout push batched with the clipboard Task) over a custom
status line: native pattern, tiny surface, exercises the dead key.

## D13: localize "Error" at the view boundary

Engine stays libcosmic-free (architecture seam), so `result_display`
keeps `"Error"` for logs/tests and `display()` substitutes
`fl!("error")` when `state.error.is_some()`. Correctness > purity:
translators see the key, tests stay deterministic.

## D14: save only on persisted-state mutations

Persisted = mode/angle/history. `needs_save()` gates `Equals`,
`ClearHistory`, `ToggleAngle` (+ nav-select path). Digits/ops/recall
never touch the store. Chosen over debounce timers: deterministic,
no background tasks, trivially testable.

## D15: sanitize loaded history; clamp recalled entry

`sanitize_persisted()` (100 entries, 256 chars/field) called from
`config::load`; recall/ans clamp to MAX_ENTRY_LEN. Trust boundary is
the config file (shared, user-editable, sandbox-migrated). Fail-closed
(truncate) rather than fail-open or refuse-to-start.

## D16: no dependency upgrades in this audit

Pinned libcosmic rev + lockfile build green with no advisory driver
in scope; GUI-rev churn risks weeks of API drift for zero user gain.
Revisit only on concrete security/correctness cause.

## D17: keep binary-crate test mirror

Extracting a lib target would churn Flatpak manifest paths for
marginal gain; the integration mirror is marked "kept in sync" and
calls identical engine methods. Revisit if the mirror ever drifts.

## D18: plain `h` toggles history despite hex mode

`h` is never a hex digit (a–f only), so no conflict in programmer
mode; honors the ux keyboard contract without mode-scoping.
