# Changelog

## 0.2.0-alpha.1 — unreleased migration preview

- Replace the Linux-only COSMIC frontend with one Rust/Dioxus Desktop frontend,
  portable command/state/persistence layers and native menu/clipboard integration.
- Preserve all three calculator modes, useful functions, history and shortcuts.
- Fix shifted operators, invalid programmer digits, numeric history recall across
  bases, unbounded expression recursion, collapsing small-window controls and
  silently ignored save failures.
- Add System/Light/Dark preferences, native desktop commands and saved window size.
- Import old Linux RON settings automatically, preserve originals/backups, and
  protect malformed, oversized or future-version configuration.
- Add real desktop automation and Windows/macOS/Linux/Flatpak packaging/CI.
- Backport an upstream GLib iterator safety fix required by the Linux WebKit host.
- Linux native QA passes. Other platforms, Flatpak and hosted workflows remain
  unvalidated here; see PLATFORM_SUPPORT.md. This is not a stable release.

## 0.1.0 — 2026-09-11

Original Linux/libcosmic calculator with standard, scientific and programmer
modes, keyboard control and persistent history. Baseline source and runtime
behavior are recorded in MIGRATION_AUDIT.md.
