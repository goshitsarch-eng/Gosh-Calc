# Performance — Gosh Calc

## P-1 — config written on every keystroke (fixed, B7)

Evidence: `App::update` called `config::save` after every `reduce`,
including `Digit`/`Dot`/`Backspace`. `save` serializes the full
`history: Vec<HistoryEntry>` (up to 100 entries) through a
cosmic-config transaction → filesystem write per keypress.
Impact: O(history) disk I/O per keystroke; also wears on
battery/SSD for zero benefit since digits never alter persisted
state (mode/angle/history). Fix: `needs_save(&Message) -> bool`
gate — save only on `Equals`, `ClearHistory`, `ToggleAngle`
(nav-select saves via existing path). Before/after: per-keystroke
transaction+serialize eliminated; saves now occur only on events
that mutate persisted state (test `save_gating` pins the mapping).

## Non-issues (measured by reasoning, no change)

- `view()` rebuilds ≤49 small buttons per frame: normal iced
  immediate-mode cost, no expensive work (no parsing, no I/O, only
  string formatting of two display lines). Not touched.
- Single keyboard subscription, no timers/polling/background tasks;
  idle CPU = event-driven zero. Clipboard/history Tasks are
  one-shot. No stale-async risk (no async state at all).
- History drawer renders ≤100 rows in a scrollable: trivial.
- Engine clones are small (`Vec<Token>` of Copy values, short
  strings); `context_value` clones tokens only on `%` press.
- Startup: parses no files except cosmic-config (tiny); i18n
  fallback embedded. Cold start dominated by libcosmic/wgpu init,
  out of scope.
- No images/thumbnails/caches/network/DB. Flatpak startup standard
  freedesktop runtime; `--device=dri` with llvmpipe fallback.
