# APP-INVENTORY — Gosh Calc

Auditor-generated inventory of every user-facing capability in
Gosh Calc (`dev.goshapps.calc`, v0.1.0), each traced from UI entry
point through `Message` → `update`/`reduce` → engine → visible
feedback. Nothing below is claimed from a button label alone.

- Audit date: 2026-09-12. Method: full read of all 4 Rust sources
  (`src/main.rs`, `src/engine.rs`, `src/config.rs`, `src/i18n.rs`),
  `tests/integration.rs`, i18n assets, desktop/metainfo/icon,
  Flatpak manifest, both scripts, all docs in `docs/design` and
  `docs/audit`, plus `cargo test` (observed this session:
  34 bin + 37 integration-target tests, 0 failed).
- Repo shape: binary-only crate, no lib target, no `SetMode`
  message (mode travels via nav-bar selection), no CLI parsing,
  no menus, no dialogs, no settings page, no network, no file
  open/save, no import/export, no search/filter/sort, no system
  notifications, no background tasks.
- Line numbers refer to the tree as audited; `M=` is
  `src/main.rs`, `E=` is `src/engine.rs`, `C=` is `src/config.rs`.

## Capability map (summary)

| # | Capability | Status |
|---|-----------|--------|
| 1 | Single window, header bar, title | Working |
| 2 | Mode navigation (nav bar, 3 modes) | Working |
| 3 | Expression + result display | Working |
| 4 | Standard keypad (arithmetic, %, 1/x, x², √) | Working |
| 5 | Scientific keypad (powers, roots, logs, trig, parens, EE, Ans, π/e) | Working |
| 6 | Programmer keypad (bases, readout, bitwise, shifts, modulo) | Working |
| 7 | Operator precedence + chaining + repeat-equals | Working |
| 8 | History drawer (list, recall, clear) | Working |
| 9 | Copy result + toast feedback | Working |
| 10 | Full keyboard map incl. numpad | Working |
| 11 | Error display + recovery | Working |
| 12 | Persistence (mode, angle, history) | Working |
| 13 | Localization (Fluent, English baseline) | Working, single locale |
| 14 | Theming (light/dark via COSMIC/portal) | Working |
| 15 | Accessibility (a11y, labels, tooltips, keyboard-only use) | Working |
| 16 | Desktop entry, metainfo, icon | Working |
| 17 | Flatpak build + smoke scripts | Working |
| 18 | CLI arguments | Absent (by design) |
| 19 | Menus / dialogs / settings pages | Absent (by design) |
| 20 | Memory keys (M+/MR/MC), single-instance | Absent (deferred, D8) |
| 21 | Notifications, network, file I/O, import/export, search | Absent (no surface) |

## 1. Single window, header bar, title

- Where accessed: application launch (`cargo run`, installed
  `gosh-calc` binary, `flatpak run dev.goshapps.calc`).
- Implementation: `M:23-29` (`main`, 430x560 default size);
  `M:271-276` (header + window title via `fl!("app-title")`);
  `M:290-299` (`header_end`, history toggle only).
- Status: working. One window, resizable, keypad stretches via
  `Length::Fill` (`M:428-467`).
- Limitations: no minimum-size API in this libcosmic rev; the
  8-column scientific grid is dense at minimum width. No window
  size/state persistence (platform behavior, intentional).
- Config requirements: none.
- Documented: yes — `README.md`, `docs/design/ux.md` §Window.
- Docs accurate: yes.

## 2. Mode navigation (Standard / Scientific / Programmer)

- Where accessed: COSMIC nav bar, three entries.
- Implementation: nav model built `M:235-247`, persisted mode
  activated `M:256-262`, `nav_model()` `M:279-281`,
  `on_nav_select()` `M:283-288` → `CalcState::set_mode` `E:769-808`
  → `config::save` `C:43-61`. Pads swap in `view()` `M:410-414`.
- Status: working. Switching converts the in-flight value between
  domains (float↔i64 with clamp, `E:774-783`); leaving programmer
  mode resets base to DEC (`E:785-787`).
- Limitations: none functional. Standard mode rejects parens
  (`E:560,579`); bitwise/modulo and NOT are programmer-gated
  (`E:115-123`, `E:171-184`).
- Config requirements: mode string persisted via cosmic-config
  file backend (`C:22-29`, `C:46-50`); works without COSMIC
  session services.
- Documented: yes — README, ux.md §Navigation, metainfo.
- Docs accurate: yes. Note `docs/design/architecture.md` names a
  `SetMode` message that does not exist — mode travels via
  `on_nav_select`, never via `Message`. That doc line is stale.

## 3. Expression + result display

- Where accessed: top of the window in every mode.
- Implementation: `App::display` `M:470-552`; small caption
  expression line (`E:302-314`) + copy button row (`M:485-494`);
  large `title2` result line (`M:496-501`) fed by
  `result_display()` (`E:319-338`) with view-boundary localized
  error substitution (`M:476-480`).
- Status: working. Live preview evaluation while typing
  (`E:937-943`); typed states like `0.` preserved (`E:323-328`).
- Limitations: expression line intentionally clears after `=`
  (ux spec; record lives in history). No thousands separators
  (copy/paste friendly, intentional). Float formatting is 12
  significant digits (`E:1265-1319`).
- Config requirements: none.
- Documented: yes — ux.md §Display.
- Docs accurate: yes.

## 4. Standard keypad

- Where accessed: Standard mode, 4 cols x 6 rows (`M:554-595`).
- Implementation: `%`→`Message::Percent`→`input_percent`
  (`E:634-659`, GNOME context semantics: `200+15%`=230);
  `CE`/`C`/`Del`→clear entry/all/backspace (`E:434-460`);
  `1/x`, `x²`, `√`→`input_unary` (`E:613-632`); `÷×−+`→
  `input_binary` (`E:507-557`); digits/`±`/`.`/`=` as listed.
- Status: working. Verified wired: every key carries
  `Some(Message::…)` (`M:557-594`) and `reduce` handles each
  (`M:65-90`).
- Limitations: no parens in standard mode (by design); `±` on
  empty entry inserts `-0` path (`E:425-431`); backspace after
  `=` is a no-op (GNOME convention, must use CE/C).
- Config requirements: none.
- Documented: yes — README, ux.md keypad sketch.
- Docs accurate: yes; sketch matches shipped grid.

## 5. Scientific keypad

- Where accessed: Scientific mode, 8 cols x 6 rows (`M:597-668`).
- Implementation: `x² x³ √ ∛ 1/x x!`→`UnaryOp` (`E:990-1088`);
  `xʸ y√x`→`BinOp::Pow/YRoot` (precedence 5, right-assoc,
  `E:82-96`); `sin cos tan ln / inverses / log / eˣ 10ˣ`→
  `apply_unary` (`E:990-1074`, DEG/RAD aware `E:1090-1102`,
  epsilon-snapped `E:1053-1066`); `π e`→`input_const` (`E:494-505`);
  `EE`→`input_exp` (`E:463-479`); `Ans`→`input_ans` (`E:482-492`,
  newest history result); `(` `)`→paren input (`E:559-611`,
  auto-close at `=` via `committed_tokens` `E:922-934`);
  `DEG/RAD` toggle key (`M:658`) → `toggle_angle` (`E:829-834`,
  persisted); `|x|`→`Abs`; `%`→context percent.
- Status: working. All keys wired with `Some(Message::…)`
  except the intentional layout `gap()` (`M:665`).
- Limitations: unary ops apply immediately to the entry (D5) —
  history shows the evaluated operand, not symbolic `sin(30)`.
  Factorial accepts only 0..=170 integers (`E:1076-1088`).
  `(` mid-entry rejected (no implicit multiplication, `E:564`).
- Config requirements: none, except angle unit persists
  (`C:30-34`).
- Documented: yes — README, ux.md sketch.
- Docs accurate: yes.

## 6. Programmer keypad + base readout

- Where accessed: Programmer mode; readout + HEX/DEC/OCT/BIN
  selector in the display (`M:503-533`); 6 cols x 6 rows
  (`M:672-736`).
- Implementation: `base_readout()` (`E:341-352`, u64 bit-pattern
  formatting); `SetBase`→`set_base` (`E:810-827`, reinterprets
  entry); A–F keys enabled only in HEX (`M:676-683` plus
  `digit_valid` gate `E:59-62`); `<< >> AND OR XOR`→bitwise
  binary ops (wrapping i64, `E:1107-1118`); `NOT`→`!` (`E:991`);
  `%`→`BinOp::Mod` (`E:638-640`); integer `+−×÷` with checked
  ops, truncating division (`E:1122-1156`); parens allowed;
  `.` rendered inert (`key(".", Digit, None)`, `M:722`).
- Status: working. Exact 64-bit two's-complement (D6); `NOT`
  of `0x…FF00` verified by test.
- Limitations: integers only (no dot/EE/Ans/π/const — engine
  rejects, `E:395-397,463-465,494-496`); shifts use
  wrapping semantics so huge/negative counts never panic;
  negative hex entry uses two's-complement negate display.
  Base resets to DEC on relaunch (documented contract).
- Config requirements: none (base is deliberately NOT persisted).
- Documented: yes — README (incl. the DEC-reset note), ux.md.
- Docs accurate: yes. ux.md's note that "digit keys outside the
  current base are disabled" is true at the engine gate; the pad
  itself only disables A–F and `.` (digits 2-9 are accepted by
  the button but ignored by `input_digit`, same net effect).

## 7. Precedence, chaining, repeat-equals, editing

- Where accessed: typing + `=` in all modes.
- Implementation: precedence climbing `eval_tokens` (`E:1191-1249`)
  with C-like ordering (`E:82-91`); op correction (`2+×`→`2×`,
  `E:527-532`); unary minus handling (`E:511-543,1238-1246`);
  repeat slot recorded at `=` (`E:699`) and re-applied on bare
  `=` (`E:666-696`); bare `=` with nothing committed updates
  display but records no history (`E:725-727`); backspace
  (`E:434-444`), CE (`E:446-451`), C (`E:453-460`), sign toggle
  (`E:412-432`); 32-char entry cap (`E:12,380`).
- Status: working; covered by `precedence`, `chained_and_repeat`,
  `continue_after_equals`, `op_correction`, `unary_minus`,
  `backspace_and_clear`, `bare_equals_records_no_history` tests.
- Limitations: no implicit multiplication (`2(3)` rejected).
  Repeat-equals records one history entry per press (intended).
- Config requirements: none.
- Documented: yes — README (chained/repeat-equals), architecture.md.
- Docs accurate: yes.

## 8. History drawer

- Where accessed: header-end `document-open-recent-symbolic` icon
  button (`M:290-299`) with tooltip; `h`/`H`/Ctrl+H keyboard;
  context drawer titled History (`M:301-337`).
- Implementation: `ToggleContext` flips `show_context`
  (`M:352-355`); drawer lists newest-first `MenuItem` rows
  (`M:312-322`) showing expr + result; row press→`Recall(i)`→
  `recall_history` (`E:741-750`, clamped to 32 chars, drawer
  stays open per spec); footer destructive Clear→
  `ClearHistory`→`clear_history` (`E:763-765`), disabled when
  empty via `on_press_maybe(None)` (`M:328-334`); cap 100
  (`E:13,737`); empty state `fl!("history-empty")` (`M:309-311`).
- Status: working. Recall of hostile-but-parseable strings shows
  raw until next key (self-heals, accepted residual per REPORT).
- Limitations: newest-first only; no per-entry delete, no search,
  no edit. Drawer does not close on recall (intentional).
- Config requirements: history persisted (`C:35-41,57`) with
  sanitize-on-load (100 entries / 256 chars per field, `E:755-761`).
- Documented: yes — README, ux.md §History, metainfo.
- Docs accurate: mostly. ux.md says entries list
  `expression = result`; the shipped UI shows two stacked lines
  (expr caption, result title) with no `=` glyph. Minor wording
  drift. `docs/audit/FEATURES.md` rows on history persistence
  ("saves on every keystroke") and clear-button arming describe
  the pre-fix baseline, not the shipped code — stale.

## 9. Copy result + toast feedback

- Where accessed: copy icon button in the display row (`M:489-491`,
  `edit-copy-symbolic`, tooltip `fl!("copy")`); Ctrl+C /
  Ctrl+Insert keyboard.
- Implementation: `Message::CopyResult`→`update` (`M:341-348`):
  `result_display()` → `iced::clipboard::write` batched with a
  `Toasts::push(Toast::new(fl!("copied")))`; `ToastClose`
  (`M:349-351`); overlay wraps view root (`M:415`); toasts owned
  in `App` (`M:194,269`).
- Status: working. Copies the raw result string (no separators,
  copy-friendly).
- Limitations: copies result/entry only (not the expression
  line); no copy-history or copy-all. In-app toast only — no
  system notification (desktop file correctly sets
  `X-GNOME-UsesNotifications=false`).
- Config requirements: none (compositor clipboard; no extra
  Flatpak permission needed on Wayland).
- Documented: yes — README, ux.md §Copy.
- Docs accurate: yes. `docs/audit/FEATURES.md` "partial — NO
  feedback" row is pre-fix and stale; the toast is shipped.

## 10. Keyboard map (incl. numpad)

- Where accessed: global `event::listen_with` subscription
  (`M:385-399`); no focus required.
- Implementation: `key_message` (`M:93-187`), total function
  (no unwrap); Ctrl layer: Ctrl+C copy, Ctrl+H history,
  Ctrl+Insert copy (`M:101-114`); numpad codes handled
  physically incl. numlock-independent ops (`M:117-130`); chars:
  digits, `./,` dot, `+−*/^%=` (`^` mode-scoped: XOR in
  programmer, Pow elsewhere, `M:152-156`), parens, `!`→Fact,
  `&|<>~` bitwise, `p`→π in scientific (`M:167`), `a-f`→hex
  digits in programmer-HEX (`M:168-180`), bare `h`→history
  (`M:182`); Enter=, Backspace, Delete=CE, Esc=C (`M:132-135`).
- Status: working. Pinned by shell tests (`M:755-796`).
- Limitations: `! & | < > ~` are accepted as keys in every mode
  but engine-gated (`allowed_in`) outside their modes — no-op,
  no error shown. No `e` shortcut for Euler's constant (only
  the pad button). No arrow-key editing, no Tab traversal
  customization (libcosmic defaults).
- Config requirements: none.
- Documented: yes — README §Keyboard, ux.md §Keyboard input.
- Docs accurate: yes. README omits Ctrl+H (documents `h` only)
  though both work — underspecification, not an error. ux.md
  documents `h` without mentioning Ctrl+H likewise.

## 11. Error display + recovery

- Where accessed: result line, all modes.
- Implementation: `CalcError` variants (`E:192-211`: DivByZero,
  Overflow, Domain, InvalidExpr, OutOfRange); engine surfaces
  `"Error"` (`E:320-322`); view substitutes `fl!("error")`
  (`M:476-480`) keeping the engine libcosmic-free; any digit
  clears into a fresh entry (`E:365-368`); backspace/CE also
  clear (`E:434-451`); dot/sign/unary/binary are rejected while
  errored (`E:395,413,508,614,635`).
- Status: working; no panic path (checked/wrapping int ops,
  NaN/inf → Domain/Overflow, fuzz tests
  `rapid_state_churn_no_panic`, `huge_operands_no_panic`).
- Limitations: single generic on-screen string; specific cause
  exists only in `error`/`Display` for logs/tests. Overflow on
  `x²`-style float overflow surfaces as Overflow; programmer
  `Pow` with negative exponent → Overflow.
- Config requirements: none.
- Documented: yes — README ("Errors show `Error`…"), ux.md §Display.
- Docs accurate: yes for the English locale (the only shipped
  locale renders `Error`). `docs/audit/FEATURES.md`
  "English-only hardcode" row is pre-fix and stale.

## 12. Persistence (mode, angle, history)

- Where accessed: automatic; load in `init` (`M:249-262`), save
  on persisted-state mutations only.
- Implementation: `config::store/load/save` (`C:11-61`),
  `Config::new(APP_ID, 1)` file backend (no dbus-config per D2);
  `needs_save` gate (`M:200-205`): `Equals`, `ClearHistory`,
  `ToggleAngle`; nav-select saves via its own path (`M:283-288`);
  everything else skips the disk write. Load clamps via
  `sanitize_persisted` (`E:755-761`).
- Status: working; gating pinned by test
  `save_gating_pins_persisted_state_policy` (`M:798-817`).
- Limitations: base NOT persisted (resets to DEC — documented
  contract); entry/expression not persisted; store failure
  degrades silently to defaults with a warn log (`C:14-17`).
- Config requirements: writable XDG config dir
  (`~/.config`, inside the sandbox for Flatpak). No COSMIC
  session services needed. `CONFIG_VERSION = 1` (`C:9`).
- Documented: yes — README (incl. base-reset note), ux.md
  §Settings & persistence, architecture.md §Persistence.
- Docs accurate: yes.

## 13. Localization

- Where accessed: automatic system-language selection at startup.
- Implementation: `i18n::init` (`C analogue M:25`, `src/i18n.rs:24-30`)
  via i18n-embed + Fluent + `DesktopLanguageRequester`;
  `fl!` macro (`src/i18n.rs:32-40`); 12 keys in
  `i18n/en/gosh_calc.ftl` (app-title, 3 modes, history x3,
  copy, copied, deg, rad, error); fallback `en` (`i18n.toml`).
- Status: working for the single shipped locale. All chrome
  strings (title, modes, history, copy, deg/rad, error) go
  through `fl!`. Keypad labels (`sin`, `x²`, `HEX`) are
  intentionally literal symbols, not translated.
- Limitations: English only — no other locale directories.
  No in-app language switcher (follows system).
- Config requirements: none (embedded via RustEmbed; works offline).
- Documented: yes — ux.md §Accessibility & i18n, architecture.md §i18n.
- Docs accurate: yes.

## 14. Theming (light/dark)

- Where accessed: automatic, follows COSMIC theme or the
  settings portal on other desktops.
- Implementation: all widgets use `theme::*` classes and spacing
  (`M:428-445` key classes: Standard digits/actions, Text ops,
  Suggested `=`); `xdg-portal` feature enabled (`Cargo.toml:17`);
  no hardcoded UI colors.
- Status: working (visual; no automated test — consistent with
  the rest of the suite being logic-level).
- Limitations: none known.
- Config requirements: none; settings portal used when present.
- Documented: yes — metainfo ("Light and dark theme
  integration"), audit COSMIC-UX.
- Docs accurate: yes.

## 15. Accessibility

- Where accessed: throughout the UI.
- Implementation: `a11y` libcosmic feature (`Cargo.toml:13`);
  text labels on all keypad buttons; tooltips + descriptions on
  the two icon-only buttons (history `M:291-298`, copy `M:489-491`);
  toast announces copy; full keyboard operation, no pointer-only
  paths (`M:385-399`); focus indicators are libcosmic defaults.
- Status: working to the extent automatable; AccessKit wiring
  comes from the framework.
- Limitations: no automated a11y test; no high-contrast-specific
  handling beyond theme inheritance.
- Config requirements: none.
- Documented: yes — ux.md §Accessibility & i18n, REPORT §Accessibility.
- Docs accurate: yes.

## 16. Desktop entry, metainfo, icon

- Where accessed: app launcher / software center.
- Implementation: `resources/dev.goshapps.calc.desktop`
  (Name/Comment/Exec/Icon/Categories/Keywords, no MimeType,
  no actions — correct, the app handles no files);
  `resources/dev.goshapps.calc.metainfo.xml` (id, license,
  description, 6-bullet feature list, launchable, developer,
  homepage/bugtracker URLs, keyboard+pointing, OARS, 0.1.0
  release, provides binary);
  `resources/icons/hicolor/scalable/apps/dev.goshapps.calc.svg`
  (fixed art, valid XML).
- Status: working. `desktop-file-validate` and
  `appstreamcli validate --pedantic` pass with advisories only
  (multi-category hint; developer-id info), per REPORT and
  enforced by `scripts/verify.sh`.
- Limitations: Keywords cover EN only; no screenshots in metainfo.
- Config requirements: none.
- Documented: yes — `docs/design/packaging.md`, REPORT §Flatpak/packaging.
- Docs accurate: yes, except packaging.md names the manifest
  `flatpak/dev.goshapps.calc.yaml` — the file is `.yml`. Stale suffix.

## 17. Flatpak build, smoke, verify scripts

- Where accessed: `scripts/verify.sh`, `scripts/smoke.sh`,
  `flatpak/dev.goshapps.calc.yml`, `flatpak/cargo-sources.json`.
- Implementation: manifest (Freedesktop runtime/SDK 25.08,
  rust-stable extension, offline vendored cargo build,
  minimal finish-args: wayland, fallback-x11, ipc, dri —
  no network/filesystem/bus); verify runs fmt→clippy→test→
  desktop/metainfo validation→flatpak build→smoke, nonzero on
  failure; smoke installs, launches under Wayland/headless
  weston/X11, asserts 10 s liveness with no panic/fatal, kills
  cleanly.
- Status: working per REPORT (force-clean rebuild + smoke PASS
  observed in audit; not re-run in this inventory pass — build
  artifacts `build-dir/`, `.flatpak-builder/` present in tree).
- Limitations: smoke needs a display path (existing Wayland,
  weston, or X11) or it exits 1. `cargo-sources.json` must be
  regenerated after every `Cargo.lock` change (documented
  command in README + manifest notes).
- Config requirements: flatpak-builder + SDK for the build;
  none at app runtime beyond the four finish-args.
- Documented: yes — README §Flatpak, packaging.md, REPORT.
- Docs accurate: mostly. packaging.md says smoke uses
  "weston headless backend or Xvfb + x11 socket" — the script
  actually prefers an existing Wayland session, then headless
  weston, then an existing X11 `DISPLAY`; no Xvfb. Stale detail.

## 18. CLI arguments — absent

- Where accessed: n/a. `main()` (`M:23-29`) parses no arguments;
  no clap/lexopt dependency; desktop `Exec=gosh-calc` takes none.
- Status: absent by design (no spec requirement; nothing to pass —
  no files, no expressions, no eval-and-print mode).
- Documented: accurately undocumented — no doc claims CLI flags.
- Docs accurate: n/a (no claims made).

## 19. Menus / dialogs / settings / about pages — absent

- Where accessed: n/a. No menu bar, context menus, modal dialogs,
  settings view, or about view exist in `view()` (`M:401-417`),
  `header_end` (`M:290`), or the drawer (`M:301`). The only
  overlay is the history context drawer + toaster.
- Status: absent by design (not specified; DECISIONS silent =
  not required; audit FEATURES row marks "missing (not
  specified; intentional)").
- Documented: accurately undocumented.
- Docs accurate: n/a.

## 20. Memory keys / single-instance — absent (deferred)

- Where accessed: n/a. No M+/MR/MC keys on any pad; no zbus
  single-instance gating in `main()`.
- Status: absent, explicitly deferred by D8
  (`docs/design/DECISIONS.md:89-96`).
- Documented: yes — README §Known limitations.
- Docs accurate: yes.

## 21. Notifications / network / file I/O / import-export / search — absent

- Implementation evidence of absence: `grep` over `src/` finds no
  notification, network/http, `Command`/process, file-dialog, or
  import/export symbols; `Toast`/`toaster` are in-app only
  (`M:15,54,194,269,343,349,415`); `Surface` (`M:55,356-360`)
  forwards window-surface actions, not user data; Flatpak grants
  no network/filesystem/bus; config touches only the app's own
  XDG config file.
- Status: absent; there is no surface for these (calculator with
  no documents, no accounts, no sync).
- Documented: accurately undocumented; SECURITY.md explicitly
  records the no-network/no-shell/no-IPC finding.
- Docs accurate: yes.

## Appendix A — message wiring table (all 19 variants)

| Message (`M:31-61`) | Producer(s) | Consumer | Verified |
|---|---|---|---|
| Digit(u8) | pads (`M:571-593` et al), keyboard (`M:137-146,168-180`) | `reduce`→`input_digit` (`M:67`) | test |
| Dot | `.` keys, `./,` + numpad decimal | `reduce`→`input_dot` (`M:68`) | test |
| Exp | `EE` key (`M:660`) | `reduce`→`input_exp` (`M:69`) | integration |
| Ans | `Ans` key (`M:661`) | `reduce`→`input_ans` (`M:70`) | integration |
| Binary(BinOp) | op keys, `+−*/^&\|<>` + numpad ops | `reduce`→`input_binary` (`M:71`) | test |
| Unary(UnaryOp) | function keys, `!`, `~` | `reduce`→`input_unary` (`M:72`) | test |
| Percent | `%` keys, `%` char | `reduce`→`input_percent` (`M:73`) | test |
| Equals | `=` keys, Enter/`=`/numpad Enter | `reduce`→`equals` (`M:74-76`) | test |
| Backspace | `Del` keys, Backspace/numpad BS | `reduce`→`backspace` (`M:77`) | test |
| ClearEntry | `CE` keys, Delete | `reduce`→`clear_entry` (`M:78`) | test |
| ClearAll | `C` keys, Escape | `reduce`→`clear_all` (`M:79`) | test |
| ToggleSign | `±` keys | `reduce`→`toggle_sign` (`M:80`) | test |
| SetBase(Base) | base selector (`M:521-533`) | `reduce`→`set_base` (`M:81`) | test |
| ToggleAngle | `DEG/RAD` key (`M:658`) | `reduce`→`toggle_angle` (`M:82`) | integration |
| Constant(Const) | `π`/`e` keys, `p` | `reduce`→`input_const` (`M:83`) | test |
| LParen/RParen | paren keys, `(`/`)` chars | `reduce` (`M:84-85`) | test |
| Recall(usize) | history rows (`M:320`) | `reduce`→`recall_history` (`M:86`) | integration |
| ClearHistory | drawer footer (`M:328-334`) | `reduce`→`clear_history` (`M:87`) | integration |
| CopyResult | copy button, Ctrl+C/Ctrl+Insert | `update` clipboard+toast (`M:341-348`) | code-read+launch* |
| ToggleContext | header button, `h`/Ctrl+H, drawer close | `update` (`M:352-355`) | code-read+launch* |
| ToastClose(id) | toaster timeout | `update` (`M:349-351`) | code-read |
| Surface(a) | framework | forwarded (`M:356-360`) | code-read |
| KeyPressed{..} | subscription (`M:385-399`) | mapped+redispatched (`M:361-373`) | test (map fn) |

*UI-layer Tasks (clipboard write, drawer flip) are not
reducer-testable; covered by code read + the audit's headless
launches. No dead variants: every `Message` has a producer and
a consumer; `reduce`'s `_` arm (`M:88`) catches only the
shell-handled variants by construction.

## Appendix B — existing-docs accuracy verdicts

- `README.md`: accurate on all claims checked (modes, history,
  copy+toast, error recovery, build/run, keyboard, Flatpak,
  limitations). Minor: omits Ctrl+H (documents `h` only).
- `docs/design/ux.md`: accurate incl. as-shipped keypad sketches;
  two drifts: history "expression = result" wording (§History)
  vs stacked two-line rows; smoke/Xvfb is in packaging.md, not here.
- `docs/design/architecture.md`: stale in three places — `SetMode` /
  `RecallHistory` / `Key(KeyBind)` message names, `config: AppConfig`
  field, and `reduce(..., msg: &InputMsg)` signature do not match
  the shipped `Message`/`App`/`reduce` shape.
- `docs/design/packaging.md`: stale manifest suffix (`.yaml` vs
  `.yml`); stale smoke backend description (Xvfb); "property-style
  checks (a+(b−b)=a, x/x=1)" misdescribes the actual fuzz tests.
- `docs/design/PLAN.md`, `docs/design/DECISIONS.md` (D1–D11): accurate.
- `docs/audit/REPORT.md`, `BUGS.md`, `DECISIONS.md` (D12–D18),
  `ARCHITECTURE.md`, `SECURITY.md`, `PERFORMANCE.md`,
  `PACKAGING.md`, `COSMIC-UX.md`, `BASELINE.md`: accurate as
  post-fix records (BASELINE correctly scoped as pre-fix).
- `docs/audit/FEATURES.md`: stale — its partial-status rows (copy
  feedback, history persistence cost, error localization, keyboard
  gaps, clear-button arming) describe the pre-fix baseline; all
  were fixed per REPORT/BUGS. Do not cite it as current state.
- `resources/dev.goshapps.calc.metainfo.xml`: accurate (feature
  bullets all verified working above).
