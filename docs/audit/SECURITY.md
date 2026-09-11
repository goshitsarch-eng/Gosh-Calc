# Security & robustness — Gosh Calc

Trust boundaries: (1) keyboard input → `key_message`; (2) persisted
config file → `config::load` (mode/angle/history strings); (3) icon/
desktop/metainfo static assets; (4) clipboard write target. No
network, URLs, files-outside-XDG, shell, processes, IPC names, D-Bus
names, portals-beyond-theme, drag-drop, archives.

## Findings

### S-1 — unbounded persisted strings (P2, fixed, B8)

`load()` assigned history verbatim; recall/ans cloned into entry
unbounded → hostile/rotted config could OOM the app or wedge the
display. Fix: `sanitize_persisted()` (cap 100 entries, 256 chars per
field) + entry clamp on recall/ans. Mode/angle parsing already
defaulted safely. Tests: `sanitize_truncates_hostile_history`,
`recall_clamps_huge_result`.

### S-2 — `unwrap()` on external input (P2, fixed, B9)

`key_message` hex path unwrapped a char iterator over
user-derived text (C). Fix: fallible chain → `None`. Test added.

### S-3 — defensive fmt/op-site hardening (P3, fixed, B10)

Two category-A unwraps converted to non-panicking fallbacks so no
code path can panic even if an invariant ever breaks.

## Cleared with no change

- Injection: no shell/process/URL/SQL anywhere (`grep` for
  Command/process/open/url: none outside clipboard write).
- Path traversal: no path construction from input; config path owned
  by cosmic-config; Flatpak grants no filesystem access.
- `unsafe`: none in crate (`grep unsafe` clean).
- Integer assumptions: programmer ops use checked/wrapping ops;
  shifts use `wrapping_shl/shr` (no panic on huge/negative counts);
  `checked_pow` gates negative exponents; float paths check
  NaN/inf → Domain/Overflow. Fuzz-style `rapid_state_churn_no_panic`
  + `huge_operands_no_panic` pass.
- DoS via input: entry capped at 32 chars at the digit gate;
  history capped at 100; recall/ans now clamped.
- Secrets/PII in logs: logging is warn-only on config failures,
  never logs entry/history/clipboard. No credentials exist.
- Flatpak permissions minimal and justified: wayland, fallback-x11,
  ipc, dri. No network, no home, no bus names, no devices beyond
  dri (llvmpipe fallback documented). xdg-portal feature only
  follows host theme.
- Dependencies: pinned libcosmic rev + Cargo.lock; noSupply-chain
  upgrade performed (no advisory driver; upgrades deferred per
  policy — see DECISIONS). `cargo audit` not installed in this
  environment; vendored Flatpak build is offline.
- Startup `expect()` on embedded i18n fallback: category A
  (build-time asset via RustEmbed). A missing asset means a broken
  build, not a runtime condition. Kept + documented.
