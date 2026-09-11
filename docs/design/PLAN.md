# Gosh-Calc Implementation Plan

Consolidated by the lead from ux.md, architecture.md, packaging.md.
Reviewed by devil's advocate.

## Feature checklist

Standard mode:
- [ ] digits 0-9, decimal point, sign toggle
- [ ] +, -, x, / with correct precedence (2+3x4 = 14)
- [ ] chained evaluation and repeat-equals (2+3=5, = -> 8)
- [ ] percent (context-aware: 100+10% = 110; 200x10% = 20)
- [ ] backspace, clear entry, clear all

Scientific mode:
- [ ] parentheses (incl. auto-close at =)
- [ ] powers x^2, x^3, x^y; roots sqrt, cbrt, y-root
- [ ] log, ln, e^x, 10^x, x!, 1/x
- [ ] sin, cos, tan + inverses; DEG/RAD toggle
- [ ] constants pi, e
- [ ] scientific-notation display for extreme magnitudes

Programmer mode:
- [ ] HEX/DEC/OCT/BIN switching, A-F input
- [ ] simultaneous four-base readout
- [ ] AND, OR, XOR, NOT, <<, >>, modulo
- [ ] two's-complement hex display of negatives

Cross-cutting:
- [ ] expression + result display
- [ ] full keyboard input incl. numpad, Enter, Esc, Backspace, a-f
- [ ] copy result (button + Ctrl+C)
- [ ] history drawer: list, recall, clear, persists across launches
- [ ] error states recover cleanly; no panics
- [ ] mode + angle + history persist across launches
- [ ] COSMIC conventions: nav bar, context drawer, header bar, theming
- [ ] works on non-COSMIC desktops (no dbus-config dependency)

## Risks

1. libcosmic API drift — mitigated by pinned rev b7288527 and building
   against its vendored source.
2. Build time of the full dep tree (~644 crates incl. wgpu) — mitigated
   by warming the cache before implementation.
3. Flatpak vendoring of git deps — flatpak-cargo-generator supports
   git sources from Cargo.lock; verified during packaging task.
4. Headless smoke test — needs weston/Xvfb present; script degrades
   gracefully with a warning if neither exists.
5. i18n-embed adds build complexity — falls back to en strings if
   locale detection fails; strings are flat keys.
6. Percent semantics differ across calculators — GNOME convention
   chosen, recorded in DECISIONS.md.

## Ordered task list (app stays buildable after each)

1. Scaffold: Cargo.toml pinned to libcosmic b7288527, minimal main.rs,
   .gitignore — builds and shows a window.
2. Engine: tokens, precedence evaluator, standard ops, percent, errors
   + unit tests.
3. Engine: scientific functions, parens, constants, angle unit + tests.
4. Engine: programmer mode (i64 domain, bases, bitwise) + tests.
5. Engine: history accumulation + fmt_f64 display formatting + tests.
6. App shell: Message enum, reduce(), view with standard keypad,
   display lines, nav bar with three modes.
7. View: scientific + programmer keypads, base segmented control,
   four-base readout.
8. History context drawer + recall + clear; header-end toggle.
9. Keyboard subscription + copy task.
10. Config persistence (mode, angle, history) via cosmic-config.
11. i18n: localizer, fluent file, fl!() for all strings.
12. Integration tests for major flows.
13. Flatpak manifest + cargo-sources.json + desktop/metainfo/icon.
14. scripts/verify.sh + scripts/smoke.sh; full local verify green.
15. Phase 3 pass; REPORT.md.
