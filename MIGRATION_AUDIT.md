# Gosh Calc migration audit

Baseline: commit `f7591699705a8d2b055f3fbcc3e0b8d043e2bd55`, version 0.1.0.
Audit performed before changing application code. Status is evidence, not a promise.
The target is 0.2.0-alpha.1, a Rust + Dioxus Desktop migration prerelease.

## Baseline evidence

Built and launched the original libcosmic application on Debian 13 x86_64,
Rust 1.99.0, Xvfb, software Vulkan and a private D-Bus session. Build, formatting,
Clippy with `-D warnings`, 41 binary tests and 37 integration-target tests passed.
The older CONTRIBUTING test count (34 + 37) is stale. The integration target
recompiles engine unit tests, so the count does not mean 78 distinct scenarios.
Native GUI checks verified precedence, copying, division by zero and recovery.
Additional mouse traversal exercised mode selectors, keypad rows and the history
drawer; screenshots were inspected at normal, 320×420 and 1200×800 sizes.
Function semantics were cross-checked against source and engine tests; mouse
traversal alone is not proof of every numeric result. Baseline process RSS was
approximately 170 MiB in this environment; this is not a platform-independent
benchmark. Reference binary/source/screenshots are retained outside the checkout
under `/workspace/.gosh-calc-env/legacy/` for local comparisons, not distributed.

## Baseline architecture and data

* `src/main.rs`: entry point, COSMIC application shell, Message reducer, Iced
  keyboard subscription, view, all three keypads, history, clipboard and tests.
* `src/engine.rs`: portable immediate-entry/token calculator; f64 standard and
  scientific arithmetic, i64 programmer arithmetic, precedence-climbing parser,
  repeated equals, history, formatting and bounded input. No external processes,
  network access or unsafe Rust in application source.
* `src/config.rs`: cosmic-config v1 file backend. Saves mode, angle and history
  on relevant commands. Linux directory is `$XDG_CONFIG_HOME/cosmic/
  dev.goshapps.calc/v1/`; individual `mode`, `angle` and `history` files use RON.
  Programmer base intentionally resets to DEC at launch; current calculation is
  temporary. History is newest first, capped at 100 records and 256 bytes/field.
* `src/i18n.rs`, `i18n/en/gosh_calc.ftl`: embedded Fluent strings. English is
  the only shipped language. The English fallback uses a startup `expect`.
* `tests/integration.rs`: a duplicate reducer mirror driving engine methods.
  Migration must test the real shared dispatcher instead.
* Major dependencies: git-pinned libcosmic and Iced/winit forks, cosmic-config,
  wgpu, Wayland/X11, accessibility, settings portal, Fluent and serde.
* Linux assumptions: COSMIC settings, icon themes searched in `/usr/share`,
  D-Bus settings portal, XDG paths and Linux-only native/Flatpak release scripts.
  There are no app file-open/save workflows, menus, dialogs, drag/drop, printing,
  notifications, URL handling, document formats or command-line options.
* Packaging: native Linux tarballs and Flatpak (Freedesktop 25.08), offline
  generated Cargo sources, desktop/AppStream/SVG assets; Linux x86_64/aarch64
  release jobs only. Flatpak was not built during the baseline audit.

## Feature inventory

`WORKING` means verified baseline source/tests or named GUI evidence. Platform
columns in PLATFORM_SUPPORT.md record new-runtime verification separately.

| Feature | Baseline / source | Intent and known issues | Migration status |
| --- | --- | --- | --- |
| Standard arithmetic, precedence, operator correction | WORKING, engine input_binary/equals | + − × ÷, live result, chained/repeated equals | VERIFIED: engine + desktop numeric flows |
| CE, C, backspace, sign, decimal | WORKING, engine input methods | Distinct entry/expression clearing; comma decimal shortcut | VERIFIED: command and desktop flows |
| Contextual percent | WORKING, input_percent | 100+10%=110; 200×10%=20 | VERIFIED: regression + desktop |
| Reciprocal, square, square root | WORKING, apply_unary | Domain errors and overflow surfaced as Error | VERIFIED: numeric callbacks |
| Scientific powers/roots, factorial, abs | WORKING, scientific_pad/apply_unary | x² x³ xʸ y√x √ ∛ 1/x x! abs | VERIFIED: every function numeric callback |
| Trig/inverse trig, DEG/RAD | WORKING, apply_unary/toggle_angle | sin cos tan asin acos atan; angle persists | VERIFIED: DEG/RAD numeric callbacks |
| Logs, exponentials, π/e | WORKING, apply_unary/input_const | ln log eˣ 10ˣ, constants | VERIFIED: numeric callbacks |
| EE, Ans, parentheses | WORKING, input_exp/input_ans/input_*paren | Auto-close on equals; unary functions act immediately | VERIFIED: desktop and regression tests |
| Programmer bases and readout | PARTIAL, set_base/base_readout | HEX/DEC/OCT/BIN exact i64; disabled A–F outside HEX; 8/9 still enabled in OCT, 2–9 in BIN | IMPROVED / VERIFIED: all invalid digits disabled |
| Integer arithmetic/bitwise/shifts/modulo | WORKING, apply_binary | Checked arithmetic, wrapping bitwise/shift semantics | VERIFIED: exact i64 and every operation callback |
| History record, recall and clear | WORKING, history methods/context_drawer | Newest first, capped at 100; recall is a numeric string without original base metadata | IMPROVED / VERIFIED: numeric cross-base recall |
| Settings persistence | PARTIAL, config.rs | Mode, angle, history; tx.set failures discarded; commit failures logged only | IMPROVED / VERIFIED: atomic writes, errors, migration |
| Copy and confirmation | WORKING, Message::CopyResult | Ctrl+C/Ctrl+Insert; plain text clipboard | VERIFIED: native clipboard + transient confirmation |
| Keyboard operators | BROKEN, main.rs subscription/key_message | '+' and '*' arrive as '=' and '8'; subscription ignores modified_key. GUI reproduced 384 for 12+3*4 | FIXED / VERIFIED: physical shifted input gives 24 |
| Keyboard history, hex letters, clear | WORKING, key_message | h/Ctrl+H; mode-aware a–f; Esc/Delete/Backspace/Enter | VERIFIED: native shortcuts and core mappings |
| Three modes and mode sizing | PARTIAL, mode_window_size/view | Correct normal sizes; 320×420 programmer keypad labels disappear and mode name clips | IMPROVED / VERIFIED: responsive grids and readable scroll |
| Theme and icons | PARTIAL, libcosmic/theme/icon fallback | Portal unavailable in headless sessions; fallback works; user cannot choose theme | IMPROVED / VERIFIED: explicit themes, embedded icons |
| English labels/localization infrastructure | WORKING, i18n | Only English shipped; retain labels and an extensible translation boundary | MIGRATED: English labels in UI/platform; unused Fluent removed |
| Native application menus / About / Settings | NOT IMPLEMENTED | Add appropriate shared/native desktop commands | ADDED / VERIFIED: Linux native menus and dialogs |
| Window geometry persistence | NOT IMPLEMENTED | Add bounded per-platform size/maximized state | ADDED / VERIFIED: bounded state and shutdown flush |
| Memory M+/MR/MC and single instance | NOT IMPLEMENTED | Explicitly deferred in original; no parity requirement | Not applicable |
| File operations, drag/drop, printing, notifications | NOT IMPLEMENTED | Calculator has no file-oriented workflow; do not add decorative controls | Not applicable |
| Windows/macOS installers and native releases | NOT IMPLEMENTED | Required migration packaging and native CI | PREPARED: native CI pending runtime evidence |
| Flatpak | UNKNOWN runtime evidence, manifest exists | Preserve app ID and minimal permissions; WebKit needs suitable runtime | VERIFIED x86_64: offline SDK build, installed sandbox 70 checks; arm64 pending |

## Defects and decisions

1. Use logical modified keyboard characters in the new UI; test shifted
   operators, parentheses, bitwise symbols and native primary modifiers.
2. Treat digit validity as shared command availability, disabling every invalid
   digit in the visible keypad. The programmer decimal key is intentionally
   disabled, not an unwired feature; replace its unused slot with useful layout.
3. Bound expression tokens/nesting to avoid stack exhaustion through repeated
   parentheses or powers. Existing entry/history bounds alone do not bound the
   recursive parser. Add regression tests.
4. Keep history strings compatible, but add numeric/base metadata to new history
   entries so cross-mode/cross-base recall is correct; preserve old RON untouched.
5. Save atomically, bound parsing, preserve corrupt files and migration backups,
   display data/persistence errors. Do not write settings per digit.
6. Replace collapsing fixed-height keypads with scrollable responsive grids.
7. Keep identity: Gosh Calc, `dev.goshapps.calc`, three modes, pill keys, cyan
   accent, history drawer, immediate unary operations and keyboard-first use.
8. Preserve immediate unary semantics and f64 precision/12 significant-digit
   formatting; this is not a symbolic or arbitrary-precision calculator.
9. The old frontend stays in version control and the external reference archive
   until new native parity is exercised. Do not distribute duplicate frontends.

## Completion tracking

For each inventory row, update migration status after implementation and tests.
The four platform runtime statuses are tracked independently in PLATFORM_SUPPORT.md.
Windows/macOS/Flatpak must not be marked VERIFIED by a Linux compile or YAML check.
The initial network policy blocked the GitHub API and Flathub. Access became
available after the environment was refreshed. Installed x86_64 Flatpak QA
passes 70 checks. Hosted CI was triggered, but every job was refused before
execution because the GitHub account has a billing lock. Windows/macOS desktop
compilation checks pass; this does not validate their installers or native UX.

## Feature checklist and code removal

Every existing calculator feature above has been identified, documented,
reimplemented and covered by core tests and/or real desktop callback checks.
The 70-check Linux desktop suite verifies all scientific function results,
programmer operations, digit callbacks, histories, themes and dialogs. Physical
X11 input and native menus supplement synthetic DOM input. Linux X11, nested
Wayland, 200% scaling and installed x86_64 Flatpak checks passed; Windows/macOS
native runtime and aarch64 Flatpak remain evidence gates in PLATFORM_SUPPORT.md. Settings, malformed data, CRLF, Unicode paths,
backups, unknown schemas and shutdown flushing have regression coverage.

Once Linux parity was exercised, the obsolete COSMIC shell, cosmic-config
module, English-only Fluent plumbing and superseded design/release documents
were removed from current paths. They remain in git at the baseline commit.
No useful language was removed: only English ever shipped. Labels are isolated
in UI/platform modules for future translation. All current build/release scripts
point to the Dioxus application; no second application is distributed.

The original RustEmbed debug binary requires its source asset directory at the
compile-time checkout path; its release mode embeds those assets. Reference
performance runs temporarily restored that one old asset, then removed it.
New UI styles/icons and test scripts are compile-time embedded in both profiles.

Performance checks measured complete app process trees, not just the parent.
Common keyboard/clipboard interactions were comparable, but the WebKit-based
process tree has higher memory use and startup cost in this environment. See
PLATFORM_SUPPORT.md for the measured limits; this remains a stability gate.
