# Documentation audit — Gosh Calc

Claim-by-claim check of every doc in the repo against the shipped code
(`src/main.rs`, `src/engine.rs`, `src/config.rs`, `src/i18n.rs`,
`tests/integration.rs`, Flatpak manifest, scripts, resources) and
behavior verified this session: `cargo test` 34 + 37 green,
`cargo fmt --check` clean, `cargo clippy --all-targets -- -D warnings`
clean, `desktop-file-validate` pass (1 hint),
`appstreamcli validate --pedantic` pass (1 info),
`flatpak-builder --show-manifest` expands, debug binary runs 10 s
headless with zero panics. Companion to
[APP-INVENTORY.md](APP-INVENTORY.md), which traces every capability to
its implementation.

Verdicts: VERIFIED / OUTDATED / INCORRECT / MISLEADING / INCOMPLETE /
UNVERIFIABLE / REDUNDANT.

## README.md

Mostly VERIFIED. Mode descriptions, history drawer, copy + toast,
error recovery, build/run commands, keyboard map, Flatpak section,
and limitations all match the code:

- Three modes with the listed functions: VERIFIED (`src/main.rs`
  keypads, `src/engine.rs` ops).
- History drawer newest-first, click to recall, clear button, cap
  100: VERIFIED (`src/main.rs:301-337`, `src/engine.rs:730-750`).
- Copy button + Ctrl+C with toast: VERIFIED (`src/main.rs:341-348`).
- `cargo build` / `cargo test` / `cargo run`: VERIFIED (ran this
  session).
- Keyboard section: VERIFIED against `key_message`
  (`src/main.rs:93-187`), including numpad handling, mode-scoped
  `^` and `p`, programmer `a-f`, Esc/Delete/Backspace mapping.
- Flatpak finish-args and `cargo-sources.json` regen command:
  VERIFIED against the manifest and repo layout.
- No memory keys / no single-instance / base resets to DEC:
  VERIFIED (`src/engine.rs:785-787`, D8).

Problems found:

1. INCOMPLETE — documents `h` for history but not Ctrl+H, though
   both work (`src/main.rs:105-113,182`). Fixed in rewrite.
2. INCOMPLETE — no install path for users (only `scripts/verify.sh`
   for developers). The Flatpak install + run commands existed only
   in `docs/audit/REPORT.md`. Fixed: README now shows install
   first.
3. INCOMPLETE — no contributing entry point and no license line.
   Fixed: README links to `CONTRIBUTING.md`, states MIT.
4. Missing AI-development transparency notice (required). Added.

## docs/design/ux.md

VERIFIED except three small drifts:

1. OUTDATED — §History says entries list `expression = result`;
   the shipped rows are two stacked lines (expression caption,
   result title) with no `=` glyph (`src/main.rs:312-322`). Fixed.
2. OUTDATED — §History names a "clock-rotate" header icon and
   §Copy a "content-copy" icon; the code uses
   `document-open-recent-symbolic` and `edit-copy-symbolic`.
   Fixed to the shipped names.
3. Keypad sketches: VERIFIED — all three match the shipped grids
   cell for cell.

## docs/design/architecture.md

Accurate on the engine model (tokens, precedence table, percent,
formatting, errors, persistence keys) but OUTDATED on shell
details that changed during implementation:

1. INCORRECT — message names `SetMode`, `RecallHistory(usize)`,
   `Key(KeyBind)`: none exist. Mode travels via `on_nav_select`,
   recall is `Recall(usize)`, keys arrive as `KeyPressed {..}`
   (`src/main.rs:31-61`).
2. INCORRECT — `reduce(state, msg: &InputMsg)`: the signature is
   `reduce(state: &mut CalcState, msg: &Message)`
   (`src/main.rs:65`).
3. INCORRECT — `App` holding `config: AppConfig` plus
   `config_store: Config`: the field is `store: Option<Config>`
   (`src/main.rs:189-195`).
4. INCORRECT — `Value = Float(f64) | Int(i64)`: variants are
   `F` / `I` (`src/engine.rs:215-218`).
5. MISLEADING — "mixing promotes to Float": the integer path
   applies only when both operands are `I`, otherwise the float
   path (`src/engine.rs:1122,1158`). Also `last_binop` is
   actually the `repeat` slot. Fixed wording.

All five fixed in place; the rest of the document stands.

## docs/design/packaging.md

1. INCORRECT — manifest path `flatpak/dev.goshapps.calc.yaml`:
   the file is `.yml`. Fixed.
2. OUTDATED — smoke "weston headless backend or Xvfb + x11
   socket": the script prefers an existing Wayland session, then
   headless weston, then an existing X11 `DISPLAY`; no Xvfb
   (`scripts/smoke.sh:24-43`). Fixed.
3. INCORRECT — "property-style checks (a+(b−b)=a, x/x=1)": the
   suite has no such tests; the robustness tests are
   `rapid_state_churn_no_panic` and `huge_operands_no_panic`.
   Fixed.
4. OUTDATED — `verify.sh` step list omits the desktop-file and
   AppStream validator gates that the script runs between
   `cargo test` and the Flatpak build (`scripts/verify.sh:23-35`).
   Fixed.
5. OUTDATED — header claims CI coverage ("tests, scripts, CI")
   but the repo has no CI workflows (no `.github/`). Fixed.

## docs/design/PLAN.md

OUTDATED — the feature checklist is entirely unchecked although
every item shipped and is test-covered. It reads as current work
but is a pre-implementation plan. Resolution: marked completed
per the shipped state so the checklist states what is true
instead of implying the app is unbuilt.

## docs/design/DECISIONS.md (D1–D11)

VERIFIED. Spot-checked against code: D2 (no `dbus-config` in
`Cargo.toml` features), D6 (`Value::I` integer path),
D8 (no memory/single-instance code), D9 (generator patch at
`flatpak/flatpak-cargo-generator.py:144`), D10
(`--disable-rofiles-fuse` in `scripts/verify.sh:39`). The
`Value::Int` spelling in D6 prose differs from the `I` variant
name but the meaning is unambiguous; left as is.

## docs/audit/* (historical records)

These document a completed hardening pass; all findings were
fixed and the tree state they describe as "fixed" matches the
shipped code. They are history, not user docs:

- `REPORT.md`, `BUGS.md`, `DECISIONS.md` (D12–D18),
  `ARCHITECTURE.md`, `SECURITY.md`, `PERFORMANCE.md`,
  `PACKAGING.md`, `COSMIC-UX.md`: VERIFIED as post-fix records.
- `BASELINE.md`: VERIFIED, correctly scoped as pre-fix (says so
  in its first line).
- `FEATURES.md`: MISLEADING if read as current state — its
  partial-status rows (copy feedback, per-keystroke saves, error
  localization, keyboard gaps, clear-button arming) describe the
  pre-fix baseline and every one was fixed. It has no scope
  header saying that. Resolution: added a dated note at the top
  pointing at `REPORT.md` for the fixed state. Otherwise left
  untouched as history.

## resources/dev.goshapps.calc.metainfo.xml

VERIFIED — all six feature bullets trace to working
capabilities; id, license, launchable, developer, release, and
`provides` entries are consistent with the repo (see
APP-INVENTORY.md §16).

## Gaps: docs that did not exist

- No contributor setup / test / lint / verify instructions
  outside scattered README lines → created `CONTRIBUTING.md`.
- No troubleshooting section anywhere → added a short one to
  `CONTRIBUTING.md` covering only observed failure modes
  (stale `cargo-sources.json`, missing SDK/weston, rofiles-fuse
  mount issue per D10).
- No per-file doc map → created `docs/documentation/PLAN.md`.
