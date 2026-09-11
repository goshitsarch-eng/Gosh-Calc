# COSMIC UX — Gosh Calc

## Chrome / header

Current: default libcosmic header with title + single header-end
icon button (history toggle) with tooltip. Relevant pattern:
header-end actions for drawer toggles. Problem: sort glyph for a
history drawer (B4). Change: `document-open-recent-symbolic`.
Verified: code review + launch.

## Navigation

Current: `nav_bar::Model` with three modes, persisted selection,
`on_nav_select` converts entry across domains. Pattern: canonical
COSMIC section nav (D3). No change — correct usage, including
nav-toggle shortcut for free.

## Context drawer (history)

Current: `context_drawer` titled History, scrollable MenuItem rows,
destructive Clear footer. Pattern: COSMIC context drawer with footer
action. Problems: footer always armed (B5); recalled entry keeps
drawer open (matches ux spec §History — intentional, kept).
Changes: disable footer when empty.

## Keypads

Current: hand-rolled grids via `button::custom` + Fill sizing +
theme classes (Standard digits/actions, Text operators, Suggested
`=`) — matches ux spec §Keypads and uses COSMIC spacing/typography
throughout. No libcosmic keypad widget exists, so hand-rolled grid
is justified (no duplication of provided components). Disabled keys
(A–F outside HEX, `.` in programmer) render inert via
`on_press_maybe(None)` — correct. No change except toast wrapper.

## Feedback: toasts (B2)

Current: none. Pattern: `widget::toaster` overlay wraps content;
`Toasts::push` yields auto-expiring `Toast`. Change: wrap view root
in `toaster(&self.toasts, root)`; CopyResult pushes `fl!("copied")`.
Verified: build + headless launch (toaster overlay renders, no
errors); push/auto-expire path reviewed against libcosmic
`Toasts::push` (tokio timeout → `ToastClose`). Pixel-level toast
appearance awaits a manual click-through on a live desktop.

## Display / errors (B3)

Current: caption expression line right-aligned, title2 result,
copy icon button with tooltip, programmer readout + base selector,
scientific DEG/RAD caption. Pattern: COSMIC type scale + spacing.
Problem: hardcoded "Error". Change: view-boundary `fl!("error")`.
Verified: launch, force div-by-zero, error line localized.

## States

Empty (history-empty string), populated, error (recoverable),
no loading state needed (fully synchronous engine). All present.

## Sizing / responsive

Grids use Fill + theme spacing; window resizable from 430×560
default. Scientific 8-column rows are dense at minimum width but
labels are short (≤6 glyphs). No minimum-size API in this libcosmic
rev for this shell shape — not forced. Headless launch covered the
default size only; narrow/wide resize behavior rests on Fill-based
layout (no fixed pixel widths anywhere in the pads) and remains a
manual check on a live desktop.

## Keyboard / focus / a11y

Global `event::listen_with` subscription (no focus needed);
`a11y` feature on; icon-only buttons have tooltips/descriptions;
text-key buttons are labeled. Fix B6 closes the spec gaps
(Ctrl+Insert, plain `h`). Focus indicators are libcosmic-default.

## Theme integration

All styling via `theme::*` (buttons, spacing, text classes) —
dark/light works through COSMIC theme, incl. outside COSMIC via
settings-portal (`xdg-portal` feature). No hardcoded colors except
the app icon SVG (correct — icons are fixed art).
