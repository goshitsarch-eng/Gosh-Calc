# Documentation plan — Gosh Calc

What each doc is for, who reads it, and what changed in this pass.
Sources of truth: the code itself, `cargo test` / clippy / fmt /
validator output observed this session, a headless launch, and
[APP-INVENTORY.md](APP-INVENTORY.md) /
[AUDIT.md](AUDIT.md).

## Map

| File | Verdict | Purpose / audience |
|---|---|---|
| `README.md` | REWRITE | First contact: users and developers. What the app is, how to install and use it, where to go next. |
| `CONTRIBUTING.md` | CREATE | Contributors: setup, tests, lint, `verify.sh`, Flatpak notes, short troubleshooting. |
| `docs/documentation/APP-INVENTORY.md` | KEEP | Feature inventory with implementation traces (this pass). |
| `docs/documentation/AUDIT.md` | KEEP | Claim-by-claim fact-check (this pass). |
| `docs/documentation/PLAN.md` | KEEP | This map. |
| `docs/design/ux.md` | REWRITE (small) | UX spec for contributors touching the view. |
| `docs/design/architecture.md` | REWRITE (small) | Module/state reference for contributors. |
| `docs/design/packaging.md` | REWRITE (small) | Flatpak/test/script reference. |
| `docs/design/PLAN.md` | REWRITE (small) | Original build plan; checklist marked to shipped state. |
| `docs/design/DECISIONS.md` | KEEP | Design decisions D1–D11; verified accurate. |
| `docs/audit/*` | KEEP | Historical hardening records; accurate as history. One scope note added to `FEATURES.md`. |

Nothing was merged or removed: the design docs each serve a
distinct contributor audience, and the audit docs are history
that git already preserves — deleting them would erase the
"why" behind the current code. No separate BUILDING/INSTALL/
DEVELOPMENT files: that content fits in README + CONTRIBUTING
without duplication.

## Per-file changes

- `README.md`: restructured as an overview (description, AI
  notice, features, install, usage, shortcuts, limitations, dev
  pointer, Flatpak, contributing, license). Added the AI
  transparency notice, user install commands, Ctrl+H, license
  line, and links. Problem before: accurate but developer-only,
  no install path, no notice.
- `CONTRIBUTING.md` (new): setup, `cargo test`, fmt/clippy,
  `scripts/verify.sh` as the standard gate, Flatpak rebuild and
  `cargo-sources.json` regen, observed-failures-only
  troubleshooting. Problem before: this knowledge lived only in
  `docs/audit/REPORT.md` and script headers.
- `docs/design/ux.md`: fixed history-row wording (stacked lines,
  no `=` glyph) and the two icon names to the shipped
  symbolic names. Audience: view contributors.
- `docs/design/architecture.md`: fixed message names, `App`
  fields, `reduce` signature, `Value` variant names, and the
  int/float dispatch wording. Audience: engine/shell
  contributors.
- `docs/design/packaging.md`: fixed manifest suffix (`.yml`),
  smoke display fallback order (no Xvfb), robustness-test
  description, missing validator gates in the `verify.sh` list,
  and the CI claim. Audience: packaging contributors.
- `docs/design/PLAN.md`: checked off the shipped items so the
  list describes the current tree instead of implying pending
  work. Kept as the build record.
- `docs/audit/FEATURES.md`: added a scope note (pre-fix
  baseline; see `REPORT.md` for the fixed state). Untouched
  otherwise.
