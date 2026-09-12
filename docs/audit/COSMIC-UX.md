# COSMIC UX — Gosh Calc

## Chrome / header

Current: default libcosmic header with title + single header-end
icon button (history toggle) with tooltip. Relevant pattern:
header-end actions for drawer toggles. Problem: sort glyph for a
history drawer (B4). Change: `document-open-recent-symbolic`.
Verified: code review + launch.

## Navigation

Was: `nav_bar::Model` with three modes (canonical COSMIC section
nav, D3). Problem (B14): at calculator widths the sidebar is
condensed behind an icon-only toggle, and the `navbar-*-symbolic`
icons exist in no fallback theme — with the Cosmic icon theme
uninstalled there was no visible mode switch at all. Now: a
text-button Standard/Scientific/Programmer row at the top of the
content view (`Message::SetMode`, persisted selection, entry
conversion unchanged). No nav sidebar; the header keeps title +
history toggle + window controls.

## Context drawer (history)

Current: `context_drawer` titled History, scrollable MenuItem rows,
destructive Clear footer. Pattern: COSMIC context drawer with footer
action. Problems: footer always armed (B5); recalled entry keeps
drawer open (matches ux spec §History — intentional, kept).
Changes: disable footer when empty.

## Keypads

Current: hand-rolled grids via `button::custom` + Fill sizing.
Was: Standard digits/actions, Text (transparent) operators — looked
broken next to real pills (B15). Now: every key a Standard pill
(`=` Suggested); named functions use the smaller `body` label so
multi-glyph captions fit narrow keys, same key same size in every
mode. Uses COSMIC spacing/typography throughout. No libcosmic
keypad widget exists, so hand-rolled grid is justified (no
duplication of provided components). Disabled keys (A–F outside
HEX, `.` in programmer) render inert via `on_press_maybe(None)` —
correct.

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

Grids use Fill + theme spacing. Was: one 430×560 window for
4/8/6-column pads — scientific labels clipped, keys bloated in
standard (B15). Now: per-mode window sizes (standard 400×580,
scientific 640×600, programmer 560×660), applied at boot from the
persisted mode and on every mode switch via `window::resize`
(ignored when maximized/tiled; Fill layout adapts). No fixed pixel
widths anywhere in the pads. Verified with live screenshots of all
three modes at their pinned sizes.

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
