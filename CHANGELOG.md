# Changelog

## 0.3.0-alpha.1 — unreleased rewrite preview

- Rewrite the whole application in Godot 4.7 (GDScript). Remove the Rust,
  Dioxus/WebView, Cargo, WiX and Rust-based packaging; no Electron or Flutter.
- Behavior is a verified port of 0.2: about 2.6 million randomized steps matched
  the Rust engine with zero mismatches; settings files are format-compatible
  (byte-identical re-save) and live in the same location.
- Exact decimal⇄double conversion replaces Godot's inexact built-ins so the
  displayed last digit is unchanged.
- New: single self-contained executable per platform (no WebKit/WebView2),
  bundled Inter/DejaVu fonts, vector copy icon, monochrome gear icon.
- Changed: Light/Dark applies to the application, not the OS title bar (Godot
  has no API for it). `--help`/`--version` are `gosh-calc -- --help|--version`.
  The Windows MSI is replaced by a zip. Settings are flushed but not `fsync`ed.
  `log`/`∛` derive from `log`/`pow` (matched Rust on all tested inputs).
- Test suite: 69 unit tests, golden corpus, 120 UI checks at 100% and 200%.
- Linux x86_64 build run and tested. Windows, macOS, Linux arm64 and Flatpak
  packages build but are untested on those platforms. See PLATFORM_SUPPORT.md.

## 0.2.0-alpha.1 — Rust/Dioxus migration preview

Replaced the Linux-only COSMIC frontend with Rust and Dioxus Desktop; fixed
shifted operators, invalid programmer digits, cross-base history recall,
unbounded expression recursion, collapsing small-window controls and silently
ignored save failures; added themes, menus, window persistence and legacy RON
import.

## 0.1.0 — 2026-09-11

Original Linux/libcosmic calculator with standard, scientific and programmer
modes, keyboard control and persistent history.
