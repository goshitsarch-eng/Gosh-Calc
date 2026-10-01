# Contributing

Read BUILDING.md for your OS, ARCHITECTURE.md for boundaries, and
MIGRATION_AUDIT.md for the old behavior and migration decisions.

```sh
python3 scripts/verify.py
cargo build --locked --features ui-test
python3 scripts/smoke.py target/debug/gosh-calc  # .exe on Windows
```

The desktop suite launches the real native WebView, requires completed checks,
and rejects missing/stale outcome files or nonzero exit. It is not included in
production builds. Without system GUI libraries use `scripts/verify.py --core`;
report that as core validation only. Flatpak QA is a separate build/install/run
from BUILDING.md and is never silently skipped by the native verification script.

Keep domain math in engine, availability/actions in commands, durable settings
in persistence/state, and native behavior in platform. All UI entry points use
the shared command dispatcher. Use Path/PathBuf, bounded parsing, checked math,
visible errors and backups. Preserve useful behavior and update the audit and
platform matrix when evidence changes. Do not duplicate the reducer in tests.

No mutable settings belong beside the executable. Do not log calculation
history. Avoid app unsafe code and shell commands. Review new dependencies for
license, maintenance and platform support; see SECURITY.md and vendor/README.md
for the current host-stack backport and dependency limitations.

Manual QA before a stable release: exercise every visible control and native
menu, real shortcuts/clipboard, error recovery, all bases, history recall/clear,
settings persistence after close/reopen, corrupted configuration, minimum and
maximized windows, high DPI, keyboard focus and screen readers, all theme modes,
Windows install/upgrade/uninstall, both macOS architectures and the installed
Flatpak. Record evidence rather than inferring support from compile results.

Version 0.2.0-alpha.N is the rewrite preview series. Native CI covers Linux x86_64/
arm64, Windows MSVC and both Mac architectures; Flatpak has two native runners.
A version tag invokes the same gates and packages before publication. See
[docs/RELEASING.md](docs/RELEASING.md). Historical 0.1 design notes remain in git
history; current root documents describe the canonical Dioxus application.
