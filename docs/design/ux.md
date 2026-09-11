# Gosh-Calc UX Specification

Owner: UX teammate. Covers the complete view layer design.

## Window

Single main window, `dev.goshapps.calc`, title "Gosh Calc". Minimum
content size follows the active keypad; window is resizable and the
keypad stretches. COSMIC header bar with the app name, a history toggle
button at the header end (opens the context drawer), and the standard
window controls provided by libcosmic.

## Navigation

Three modes via the COSMIC nav bar (`nav_bar::Model`), which also gives
us the standard COSMIC nav-toggle shortcut and icon buttons for free:

- Standard
- Scientific
- Programmer

Mode persists across launches. Switching modes preserves the current
entry value (converted between domains as needed).

## Display

Right-aligned display area at the top of every mode:

- Line 1 (small, secondary text): the expression being built, e.g.
  `12 + 3 ×`. Empty when only an entry is in progress.
- Line 2 (large, title text): the current entry or evaluated result.
- Programmer mode adds a readout line showing the current value in all
  four bases simultaneously: `HEX … DEC … OCT … BIN …`.
- Error states show `Error` (with the specific cause logged for tests),
  rendered in the result line; any digit/operator clears it into a fresh
  entry.

No thousands separators (copy/paste friendly). Scientific notation
(`e+16` style) when |value| >= 1e16 or |value| < 1e-9 (nonzero).

## Keypads

Buttons use `cosmic::widget::button`: digits and A–F use `standard`,
binary operators and utility keys use `text`, `=` uses `suggested`
(accent). Uniform sizing via `Length::Fill` in a fixed grid.

### Standard (4 cols x 5 rows)

```
CE  C   bs  ÷
7   8   9   ×
4   5   6   −
1   2   3   +
±   0   .   =
```

### Scientific (6 cols x 6 rows)

```
(   )   x!  %   CE  C
x²  x³  xʸ  y√x ʷˢˣ→  ÷   bs
√   ∛   1/x eˣ  7   8
9   ×   sin cos tan ln
4   5   6   −   log π
e   DEG ±   .   +   =
```

Rows arrange so digits 1-9/0 stay in their standard positions; exact row
order finalized in code — grid contents are fixed, documented in PLAN
checklist.

Includes: parentheses, powers (x², x³, xʸ), roots (√, ∛, y√x), log, ln,
eˣ, 10ˣ (row space permitting — otherwise recorded as deviation),
factorial, reciprocal, sin/cos/tan with inverse variants via a 2nd
toggle **or** long — decision: expose `sin cos tan` and `asin acos atan`
both in the grid (6 columns give room), DEG/RAD toggle showing current
unit, π and e, percent, ±, backspace, CE, C.

### Programmer (6 cols x 6 rows)

```
A   <<  >>  AND OR  XOR
B   C   NOT %   ÷   bs
(base segmented: HEX DEC OCT BIN)
D   E   F   7   8   9
CE  ±   ×   4   5   6
−   +   (   1   2   3
)   0   .   =   (pad)
```

A–F keys disabled outside HEX. `.` disabled in programmer mode (integers
only). `%` is modulo here, not percent. `<<`/`>>` shifts. A segmented
control (`widget::segmented_button` or a row of toggled buttons —
finalized against widget availability) selects HEX/DEC/OCT/BIN; digit
keys outside the current base are disabled.

## History

Context drawer (`app::ContextDrawer`) titled "History", toggled from the
header-end clock-rotate icon button. Entries list `expression = result`
newest first; clicking an entry recalls the result into the entry field
and closes nothing (drawer stays open). Footer: "Clear history" button.
History persists across launches (cap 100 entries).

## Keyboard input

Full keyboard coverage, handled in `subscription` via `iced::event`
listening on key presses (no focused widget required):

- 0–9 (row + numpad): digit; a–f: hex digits in programmer HEX
- `+ - * /`: operators; `^`: xʸ; `%`: percent (standard/scientific) or
  modulo (programmer); `(` `)`: parens; `.`/`,`: decimal point
- Enter, `=`: evaluate. Numpad Enter included.
- Backspace: delete last digit. Delete: clear entry. Escape: clear all.
- Ctrl+C / Ctrl+Insert: copy result. `h`: toggle history drawer.
- `& | ^ < >` handled for bitwise ops where unambiguous with `^`=xʸ —
  decision: in programmer mode `^` is XOR; in scientific mode `^` is
  power (mode-scoped meaning, same as hardware calculators).

## Copy

Copy button in the display area (content-copy icon) + Ctrl+C writes the
current result/entry to the clipboard via `iced::clipboard::write`.

## Settings & persistence

Persisted via `cosmic-config` file backend (XDG config dir), config
version 1: mode, angle unit, history. Window size/state handled by
COSMIC itself — not persisted manually (platform behavior).

## Accessibility & i18n

- All buttons carry text labels (no icon-only ambiguity) except the
  header history and copy icons, which get tooltips.
- `a11y` feature enabled for AccessKit integration.
- All user-visible strings go through `fl!()` Fluent localization
  (i18n/en/gosh_calc.ftl baseline).
- Buttons sized per COSMIC spacing; no pointer-only interactions —
  everything reachable by keyboard.
