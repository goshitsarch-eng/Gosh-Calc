# Audit report — Gosh Calc (`audit-hardening`)

## Executive summary

Gosh Calc entered the audit as a well-structured, fully working
three-mode libcosmic calculator (33 tests green, clippy clean) with
one red baseline gate (`cargo fmt --check` failed) and a set of
real-but-unpolished edges: silent copy, English-only error string,
wrong history icon, keyboard contract gaps, per-keystroke config
rewrites, unbounded persisted strings, and dead i18n keys. No P0
issues existed. All P1/P2 items are fixed and verified; the red-team
pass found one additional (P3) defect, also fixed. The tree is green
end to end: fmt, clippy `-D warnings`, 34 + 37 tests, desktop-file
and AppStream validation, force-clean Flatpak rebuild, headless
smoke PASS, and a 15 s live launch with zero panics.

## Original condition

Binary crate (`main` shell + pure `engine` + `config` + `i18n`),
pinned libcosmic rev, 26 engine unit tests + 7 integration flows,
Flatpak manifest with vendored offline sources, verify + smoke
scripts, design docs. Baseline: tests 33/33, clippy clean, fmt red,
packaging validators pass with advisories only.

## Bugs found (all fixed)

B1 fmt red · B2 copy without feedback · B3 hardcoded "Error" ·
B4 sort glyph as history icon · B5 clear-history armed when empty ·
B6 missing Ctrl+Insert / bare-`h` shortcuts · B7 config written per
keystroke · B8 unbounded persisted history/entry · B9 `unwrap()` on
keyboard text · B10 two invariant `unwrap()`s · B11 ux sketches
≠ shipped grids · B12 no root README · B13 (red-team) bare `=`
spammed history. Details + evidence in `docs/audit/BUGS.md`.

## Broken/unwired features

None fully broken. Partial: copy (worked, no feedback → toast),
error display (worked, not localized → view-boundary `fl!`),
persistence (worked, wasteful → gated saves), keyboard map (two
documented bindings missing → added). Dead strings `copied`/`error`
are now both wired — no dead UI remains.

## Functionality completed

Toast confirmation on copy; localized error line; correct history
icon; disabled clear-when-empty; Ctrl+Insert + bare-`h`; sanitized
config load; clamped recall/Ans; no-op bare `=`; README; accurate
ux sketches; verify.sh packaging gates.

## Security

S-1 unbounded config strings → truncated (100 entries / 256 chars)
+ entry clamps; S-2 keyboard unwrap → total function; S-3 defensive
fallbacks. No injection/unsafe/network surface exists; Flatpak keeps
minimal finish-args (wayland, fallback-x11, ipc, dri). `cargo audit`
unavailable in this environment (stated, not silently skipped).

## Performance

P-1: per-keystroke full-history serialize eliminated via
`needs_save()` gate (Equals/ClearHistory/ToggleAngle/nav-select
only), pinned by test. No other hot spots: event-driven, no
timers/threads/polling, ≤49 trivial widgets per frame.

## Architecture

`Toasts<Message>` joined `App` state with a `ToastClose` variant;
update() funnels keyboard-mapped messages through one path;
`needs_save()` centralizes persistence policy;
`sanitize_persisted()` bounds the load path. Engine stays
libcosmic-free. Test-mirror wart documented, kept (D17).

## COSMIC/libcosmic UX

Native toaster overlay, standard history glyph, disabled destructive
footer when empty, theme-driven widgets throughout, global keyboard
map honoring the ux contract, portal-based theming outside COSMIC.
Hand-rolled keypad grids justified (no libcosmic keypad widget).

## Accessibility

`a11y` feature on; labeled keys; tooltips/descriptions on icon-only
buttons; toast announces copy; full keyboard operation; no
pointer-only paths.

## Flatpak/packaging

Manifest verified (`--show-manifest` expands vendored sources);
force-clean rebuild green; smoke PASS (10 s, no fatals);
desktop-file-validate clean (one multi-category hint, advisory);
`appstreamcli --pedantic` clean (one developer-id info).
verify.sh now also gates both validators and passes
`--disable-rofiles-fuse` per D10.

## Tests added

Engine: `sanitize_truncates_hostile_history`,
`recall_and_ans_clamp_huge_result`, `bare_equals_records_no_history`.
Shell: `keyboard_h_toggles_history`,
`keyboard_hex_digits_mode_scoped`, `keyboard_ctrl_insert_copies`,
`keyboard_caret_is_mode_scoped`,
`save_gating_pins_persisted_state_policy`. Integration:
`flow_exp_and_ans`. Suite: 34 bin + 37 integration-target tests.

## Dependencies changed

None (D16: no churn without a security/correctness driver).

## Known limitations

No memory keys / single-instance (D8, intentional); base resets to
DEC on relaunch (documented contract); expression line clears after
`=` (ux spec); hostile-but-parseable recalled strings display raw
until next key (self-heals, no panic — accepted residual).

## Deferred (justified)

Lib-crate extraction for the test mirror (churns Flatpak paths,
mirror is marked); dependency upgrades (no driver); minimum-window
API (unavailable in this shell shape; grids use Fill + short labels).

## Build / run / Flatpak

```sh
cargo build && cargo test          # build + full suite
cargo run                          # run (no COSMIC session needed)
scripts/verify.sh                  # all gates incl. flatpak + smoke
python3 flatpak/flatpak-cargo-generator.py Cargo.lock \
  -o flatpak/cargo-sources.json    # after Cargo.lock changes
flatpak-builder --user --install --force-clean build-dir \
  flatpak/dev.goshapps.calc.yml && flatpak run dev.goshapps.calc
```

## Verification results (observed)

- `cargo fmt --check`: clean
- `cargo clippy --all-targets -- -D warnings`: clean
- `cargo test`: 34 + 37 passed, 0 failed
- `desktop-file-validate`: pass (1 advisory hint)
- `appstreamcli validate --pedantic`: pass (1 info)
- Flatpak force-clean rebuild: success, metadata compose ok
- `scripts/smoke.sh` (headless weston, 10 s): PASS, no fatals
- Live launch (headless weston, 15 s): alive throughout, 0 panics,
  0 config writes while idle (save gate confirmed at runtime)
- Marker sweep (TODO/FIXME/unwrap/expect/stub): only category-A
  `expect` (embedded i18n) + test-only uses remain, all documented

| Category | Found | Fixed | Remaining |
|---|---|---|---|
| P0 crash/corruption/unusable | 0 | 0 | 0 |
| P1 major/UX-reliability | 0 | 0 | 0 |
| P2 normal/incomplete/deviation/perf | 9 (B1–B4,B6–B9,V1) | 9 | 0 |
| P3 polish/docs/robustness | 6 (B5,B10–B13,T1) | 6 | 0 |
| Security findings | 3 (S-1–S-3) | 3 | 0 |
