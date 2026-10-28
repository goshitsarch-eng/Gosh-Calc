# Platform support and observed QA

Status for 0.3.0-alpha.1. **Verified** means executed in this task; **Built**
means the package exports without errors but was not run on that platform;
**Unrun** means no evidence. A successful export is not proof a platform works.

| Capability | Linux x86_64 (X11) | Linux arm64 | Windows x86_64 | macOS arm64 / Intel | Flatpak |
| --- | --- | --- | --- | --- | --- |
| Package builds | Verified | Built | Built | Built (unsigned) | Manifest written, not built |
| Launches, renders from the exported package | Verified (software GL) | Unrun | Unrun | Unrun | Unrun |
| Three modes, math, history, digit availability | Verified | Unrun | Unrun | Unrun | Unrun |
| Keyboard shortcuts (Ctrl) | Verified | Unrun | Unrun | Unrun (Command) | Unrun |
| Menus / About / Settings | Verified (in-window menu bar) | Unrun | Unrun | Unrun (system menu bar) | Unrun |
| Clipboard copy | Verified (X11) | Unrun | Unrun | Unrun | Unrun |
| System / Light / Dark | Light/Dark verified; live OS change Unrun | Unrun | Unrun | Unrun | Unrun |
| Settings persistence incl. close/reopen | Verified | Unrun | Unrun | Unrun | Unrun |
| Legacy RON import / backups | Verified (tests) | Unrun | n/a | n/a | Unrun |
| Responsive sizing, keyboard focus, 200% scale | Verified | Unrun | Unrun | Unrun | Unrun |
| Screen reader (AccessKit names set) | Unrun | Unrun | Unrun | Unrun | Unrun |
| Wayland | Unrun | Unrun | n/a | n/a | Unrun |
| Hosted CI | Workflows written; never run | | | | |

Windows and macOS binaries are stock Godot export templates with the project
pack embedded. macOS is unsigned and not notarized. There are no document/file
workflows, drag-and-drop, printing, notifications or URL actions, so none are
presented as features. English is the only language.

## Evidence

- **Differential test against the Rust 0.2 release**: ~2.6M randomized steps
  (5 seeds + an edge-case corpus), full application state compared after every
  step: 0 mismatches. The `log` and `∛` functions are not bit-exact libm calls
  but matched on every sampled input.
- **Test suite** (`scripts/test.sh`): 69 unit tests / 457 assertions including
  the 166k-step golden replay and Rust-written settings fixtures; 120 UI checks
  through real mouse/key events, passing at 100% and 200% UI scale.
- **Exact numerics**: 30,027 parse and 50,016 format cases match references.
- **Exported Linux x86_64 binary** (75 MB, single process) launched under Xvfb
  and rendered identically to the in-editor run. Measured RSS was ~220 MB
  with Mesa software rendering (llvmpipe inflates this); not comparable to the
  earlier WebKit/libcosmic numbers, and no startup benchmark was taken.
- Windows and macOS exports completed and the macOS bundle's `Info.plist` and
  layout were inspected, but nothing was executed.

## Known differences from 0.2

- Light/Dark/System style the application; the native title bar follows the OS
  (Godot exposes no per-window override).
- `--help`/`--version` need `--` (`gosh-calc -- --version`); Godot answers the
  bare flags with its own engine text.
- Settings are flushed and renamed atomically but not `fsync`ed.
- The Windows MSI is replaced by a zip; fonts are bundled (Inter/DejaVu), so
  glyph shapes differ slightly from the system-ui font used before. The gear
  icon is monochrome rather than a colour emoji; the copy icon is drawn.
- Clipboard failure cannot be detected beyond a feature check, so "Could not
  copy" appears only when the platform reports no clipboard.

## Remaining validation

Run the packages on real Windows, macOS (both architectures) and Linux arm64
machines; test Wayland, a real screen reader, live OS dark-mode switching,
fractional scaling, macOS global-menu behavior (Cmd+Q/Cmd+H interplay), and
build/install the Flatpak. Hosted CI must be enabled and observed to pass.
