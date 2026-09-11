# Consolidated plan — Gosh Calc audit

Owner: lead. Ordered so the tree builds after each item.

| ID | Sev | Area | Evidence | Expected | Fix | Verify | Status |
|---|---|---|---|---|---|---|---|
| B1 | P2 | fmt | `cargo fmt --check` diffs config.rs, engine.rs | clean | `cargo fmt` | fmt --check | done |
| B9 | P2 | robustness | main.rs:169 unwrap on key text | no unwrap on input | fallible chain | new unit test | done |
| B10 | P3 | robustness | engine.rs:518,1228-9 unwraps | no panic paths | if-let/fallback | existing fmt tests | done |
| B8/S-1 | P2 | security | load assigns history verbatim | bounded, truncated | `sanitize_persisted` + clamps | new tests | done |
| B7/P-1 | P2 | perf | save() every keystroke | save on persisted-state change | `needs_save` gate | new test | done |
| B6 | P2 | keyboard | missing Ctrl+Ins, plain `h` | match ux spec | key_message additions | new test | done |
| B2 | P2 | ux | copy w/o feedback | toast "Copied" | toaster wiring | build+launch | done |
| B3 | P2 | i18n | hardcoded "Error" | `fl!("error")` at view | display() branch | launch div-by-zero | done |
| B4 | P2 | ux | sort glyph for history | history glyph | icon rename | launch | done |
| B5 | P3 | ux | clear armed when empty | disabled | on_press_maybe | launch | done |
| B11 | P3 | docs | ux sketches ≠ grids | sketches = code | rewrite sketches | review | done |
| B12 | P3 | docs | no root README | README.md | add | review | done |
| V1 | P2 | verify | verify.sh lacks desktop/metainfo gates | extended script | add gates | run script | done |
| T1 | P2 | tests | EE/Ans flows untested | regression tests | integration tests | cargo test | done |
| B13 | P3 | history | bare `=` records no-op history dupes | no record | skip record when empty+no repeat | new test | done |
| RT | P1 | red team | fresh full pass after fixes | no P0/P1/P2 | fix findings | new PLAN rows | done |
| FLAT | P1 | packaging | force-clean rebuild + smoke on branch | green | run | logs | done |
| REPORT | P2 | docs | final report | REPORT.md | write | review | done |

P0 count: 0 (no crashes, corruption, or unusable states found —
error paths all recover; fuzz tests pass).
