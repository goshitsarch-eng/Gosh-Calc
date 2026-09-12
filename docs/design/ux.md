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

### Standard (4 cols x 6 rows, as shipped)

```
%   CE  C   bs
1/x x²  √   ÷
7   8   9   ×
4   5   6   −
1   2   3   +
±   0   .   =
```

### Scientific (8 cols x 6 rows, as shipped)

```
x²  x³  xʸ  y√x CE  C   bs  ÷
√   ∛   1/x x!  7   8   9   ×
sin cos tan ln  4   5   6   −
s⁻¹ c⁻¹ t⁻¹ log 1   2   3   +
eˣ  10ˣ π   e   ±   0   .   =
DEG |x| EE  Ans (   )   %   (gap)
```

Digits 1-9/0 keep their standard positions on the right; functions
fill the left. DEG/RAD toggle shows the current unit; inverse trig
(s⁻¹ c⁻¹ t⁻¹) is always visible — no 2nd-shift layer.

### Programmer (6 cols x 6 rows, as shipped)

```
A   B   C   D   E   F
<<  >>  AND OR  XOR NOT
(   )   %   CE  C   bs
7   8   9   ±   ÷   ×
4   5   6   .   −   +
1   2   3   0   (gap) =
```

Base selection (HEX DEC OCT BIN) lives in the display readout row,
not the grid. `=` spans the last cell; `.` is disabled (integers
only).

A–F keys disabled outside HEX. `.` disabled in programmer mode (integers
only). `%` is modulo here, not percent. `<<`/`>>` shifts. A segmented
control (`widget::segmented_button` or a row of toggled buttons —
finalized against widget availability) selects HEX/DEC/OCT/BIN; digit
keys outside the current base are disabled.

## History

Context drawer (`app::ContextDrawer`) titled "History", toggled from the
header-end recent-documents icon button. Entries list newest first,
each showing the expression on one line and its result below it;
clicking an entry recalls the result into the entry field
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

Copy button in the display area (edit-copy icon) + Ctrl+C writes the
current result/entry to the clipboard via `iced::clipboard::write`,
with a toast confirming the copy.

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
