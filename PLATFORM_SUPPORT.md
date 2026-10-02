# Platform support and observed QA

Status as of 2026-10-02 for 0.2.0-alpha.1. **Verified** means executed in this
task; **Prepared** means implemented/configured but not run on that platform.
Core portability is an architecture property, not proof of a native desktop.

| Capability | Windows x86_64 | macOS arm64 / Intel | Linux x86_64 X11 / Wayland | Flatpak x86_64 | Flatpak arm64 |
| --- | --- | --- | --- | --- | --- |
| Desktop compilation | Verified: MSVC target check | Verified: both target checks | Verified: debug/release | Verified: GNOME SDK 49 | Prepared |
| Three modes, math, history, digit availability | Prepared | Prepared | Verified | Verified | Prepared |
| Keyboard / native primary modifier | Prepared: Ctrl | Prepared: Command | Verified: Ctrl | Verified: Ctrl | Prepared |
| Native menus / About / Settings | Prepared | Prepared | Verified | Verified | Prepared |
| Plain text clipboard | Prepared | Prepared | Verified | Verified | Prepared |
| System / Light / Dark preference | Prepared | Prepared | Verified | Verified | Prepared |
| Settings and shutdown persistence | Prepared | Prepared | Verified, including reopen | Verified: default path and reopen | Prepared |
| Legacy RON migration / backup | Not applicable | Not applicable | Verified in tests | Verified: default path and backups | Prepared |
| Responsive sizing / keyboard focus | Prepared | Prepared | Verified | Verified | Prepared |
| Native archive / bundle / installer | MSI + zip prepared | Two .app zips prepared | Archive built and inspected | Production built/installed/launched | Prepared |
| Hosted CI | Billing lock: no steps ran | Billing lock: no steps ran | Billing lock: no steps ran | Billing lock: no steps ran | Billing lock: no steps ran |
| Wayland / Retina / Windows DPI | Windows DPI unrun | Retina unrun | Nested Wayland and 200% scaling verified | X11 verified | Unrun |

No document/file workflows, drag/drop, file associations, printing, notifications
or URL actions existed in the old calculator, so none are presented as working
features. English remains the only shipped UI language. Memory registers and
single-instance enforcement remain explicitly deferred from the baseline.

## Evidence

- Baseline built/launched before rewriting; inspected modes, history, keypad,
  errors, clipboard and resizing. See MIGRATION_AUDIT.md.
- New native debug/release build, formatting and strict application Clippy pass.
- 49 distinct Rust tests pass: 29 engine, 8 command integration, 11 migration/
  state/persistence and 1 GLib backport regression. Release-mode GLib regression
  also passes. Core-only tests execute 48; this excludes the Linux host regression.
- Real WebKit desktop suite passes 70 checks, including scientific control
  traversal (47 controls), numeric error recovery, all three modes, exact i64
  math, cross-base history, theme changes, dialogs, labels and layout.
- Installed production Flatpak uses only display sockets, IPC and DRI. It passes
  physical keyboard/clipboard, native menu/settings, default app-scoped RON
  migration/backups and close/reopen checks without extra filesystem/network
  grants. Production native and Flatpak binaries contain no UI-test trigger.
- Native production File/About and File/Quit, all three modes, theme changes and
  history/mode/theme/geometry restoration after reopen were exercised.
- Physical X11 shifted keyboard arithmetic `12+3*4` copies `24`; the original
  application produced `384` for that same shifted input.
- Real Linux light/dark screenshots are in docs/screenshots/. Minimum sizes use
  scrolling while keeping readable keys; scientific mode groups functions and
  the familiar numeric keypad in separate panels.
- Linux archive verification checks ELF architecture, executable permission,
  license, archive paths and SHA-256 coverage. Full-set verification rejects a
  release that lacks any required Windows/macOS/Linux/Flatpak artifact.

## Remaining validation

This cloud task has only Debian Linux. Windows/MSVC, macOS and their installers/
bundles must run on their native CI runners and then receive manual desktop QA.
Windows/macOS high DPI, screen-reader behavior, OS-driven live system-theme
changes and native macOS lifecycle behavior need actual platform access. Linux
window-manager maximize/minimize and screen-reader QA also remain unrun here.

Flathub and the GitHub API became reachable after the managed environment was
refreshed. The x86_64 Flatpak now builds offline in GNOME SDK 49, exports with
AppStream/icon validation, installs and passes all 70 real WebView checks.

[Hosted CI run 36943503549](https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/36943503549)
was triggered and inspected. All seven jobs failed before starting any steps:
“The job was not started because your account is locked due to a billing issue.”
Resolve the GitHub billing lock and rerun CI; there are no hosted artifacts to
inspect from that attempt. The arm64 Mac runner also reported a capacity warning.

Windows/MSVC and both macOS targets pass `cargo check --all-targets --all-features`
from Linux. These checks cover the native UI modules, but do not link, launch,
exercise installers or establish runtime OS compatibility. Native platform QA,
Linux arm64, minimum-distribution compatibility and arm64 Flatpak remain
stable-release gates.
Mac's transitive `block` 0.1.6 emits a future-incompatibility warning.

## Final local performance measurements

Measured on 2026-10-02 after disabling unused WebKit features, with no other
app or compiler active. Single warm-cache run per build on the same Debian/Xvfb/
software-rendering host.
Startup means first correct native keyboard calculation copied to the clipboard,
including automation polling. Interactions include xdotool/xclip overhead (10
repeats). PSS accounts for shared pages across the complete app process tree; RSS
sums double-count shared libraries. These are observations, not general benchmarks.

| Build | Ready (s) | Process-tree PSS (MiB) | Interaction median / max (ms) |
| --- | ---: | ---: | ---: |
| Original debug | 0.377 | 156.3 | 74.3 / 108.1 |
| Dioxus debug | 0.595 | 339.7 | 72.9 / 76.3 |
| Dioxus release | 0.538 | 326.7 | 70.6 / 75.6 |

The migration currently uses more memory and starts somewhat later than the old
app in this test. The original uses one app process; Dioxus/WebKit uses three.
PSS varies with library sharing and the local non-root library view, so it does
not establish an OS-wide memory budget. Disabling unused WebKit features has
not established lower process-tree memory use.
This performance goal is not yet met, even though common interactions are similar.
