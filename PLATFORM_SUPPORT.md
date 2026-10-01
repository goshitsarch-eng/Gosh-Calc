# Platform support and observed QA

Status as of 2026-10-01 for 0.2.0-alpha.1. **Verified** means executed in this
task; **Prepared** means implemented/configured but not run on that platform.
Core portability is an architecture property, not proof of a native desktop.

| Capability | Windows x86_64 | macOS arm64 / Intel | Linux x86_64 X11 / Wayland | Flatpak x86_64 / arm64 |
| --- | --- | --- | --- | --- |
| Standard/scientific/programmer UI | Prepared | Prepared | Verified | Prepared |
| Arithmetic, history, invalid-digit availability | Prepared | Prepared | Verified | Prepared |
| Keyboard and native primary modifier | Prepared: Ctrl | Prepared: Command | Verified: Ctrl | Prepared |
| Native menus / About / Settings | Prepared | Prepared | Verified | Prepared |
| Plain text clipboard | Prepared | Prepared | Verified | Prepared |
| System / Light / Dark preference | Prepared | Prepared | Verified | Prepared |
| Settings and shutdown persistence | Prepared | Prepared | Verified | Prepared |
| Legacy RON migration / backup | Not applicable | Not applicable | Verified in tests | Prepared: same app ID/XDG |
| Responsive sizing / keyboard focus | Prepared | Prepared | Verified | Prepared |
| Native archive / bundle / installer | MSI + zip prepared | Two .app zips prepared | Archive built and inspected | Manifest prepared; runtime blocked |
| Hosted CI | Configured, not executed | Configured, not executed | Configured, not executed | Configured, not executed |
| Wayland / Retina / Windows DPI | Windows DPI unrun | Retina unrun | Verified: nested Wayland, 200% Linux scaling | Unrun |

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
High DPI, screen-reader behavior, OS-driven live system-theme changes, native
macOS lifecycle behavior and installed-app launch need actual platform access.

Initial Flathub and GitHub API requests returned HTTP 403. After the managed
environment refresh, both destinations became reachable with the supplied
GitHub authentication. SDK installation and hosted CI execution are in progress;
no platform artifact or workflow is marked passed until its result is inspected.

Execute CI, inspect every matrix job and artifact,
install both Flatpak architectures, and record manual platform QA here before
promoting the preview to a stable release. CI configuration alone is not a pass.

## Initial performance measurements

Single warm-cache run per build on the same Debian/Xvfb/software-rendering host.
Startup means first correct native keyboard calculation copied to the clipboard,
including automation polling. Interactions include xdotool/xclip overhead (10
repeats). PSS accounts for shared pages across the complete app process tree; RSS
sums double-count shared libraries. These are observations, not general benchmarks.

| Build | Ready (s) | Process-tree PSS (MiB) | Interaction median / max (ms) |
| --- | ---: | ---: | ---: |
| Original debug | 0.400 | 125.6 | 74.7 / 92.6 |
| Dioxus debug | 0.639 | 226.5 | 74.6 / 81.6 |
| Dioxus release | 0.559 | 214.9 | 73.1 / 76.4 |

The migration currently uses more memory and starts somewhat later than the old
app in this test. Disabling unused WebKit media/WebGL/page-cache capabilities is
being evaluated; no performance improvement is claimed without new measurements.
This performance goal is not yet met, even though common interactions are similar.
