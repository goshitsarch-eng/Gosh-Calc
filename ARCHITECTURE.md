# Architecture

Gosh Calc 0.2 is a cross-platform Rust application rendered by Dioxus Desktop.
Use one frontend on Windows (WebView2), macOS (WKWebView), and Linux (WebKitGTK).
GTK is a Linux WebKit host dependency, not the application's primary widget UI.
No Node runtime, Electron, React, TypeScript or external shell commands are used.

## Layers

* `engine`: tested portable numeric/token model. It knows nothing about Dioxus,
  windows, paths, menus or platform APIs. Keep exact i64 programmer semantics.
* `commands`: one action enum and reducer used by keypad, keyboard, menus and
  history. Availability and persistence effects live here. Keyboard mapping uses
  modified logical key values and a platform-specific primary modifier policy.
* `state`: application model, persisted preferences and temporary presentation
  state. Calculation state is never duplicated in components.
* `persistence`: versioned JSON in standard per-platform config directories,
  bounded reads, atomic writes, corrupt-data preservation and automatic
  read-only migration of legacy cosmic-config RON files. New history metadata
  handles bases correctly; old strings remain accepted. Base resets to DEC.
* `platform`: Dioxus Desktop window and native menu integration, clipboard,
  native primary modifier, window geometry. OS conditionals stay at this boundary.
* `ui`: small display/keypad/history/settings/dialog components, CSS tokens and
  shared command callbacks. No arithmetic or filesystem operations in components.

## Runtime and data

The calculator does not require network access, external services, file dialogs,
printing or document associations. Assets are embedded at compile time so launch
does not depend on cwd or mutable files beside the executable. HTML renders user
history as text; no user input is interpolated into executable JavaScript.

Small bounded settings writes occur only on durable changes, not every keystroke.
Errors are Results, logged without history contents, and exposed in the UI.
Persistence has a dedicated worker to keep disk latency off the UI thread and
flush pending updates at exit. Native clipboard stays on the UI thread; it is
text-only and clipboard ownership remains alive while the app runs. On Linux,
the existing WebKit GTK host supplies its Wayland/X11 clipboard rather than
requiring an optional compositor data-control protocol. Windows/macOS use arboard.
Mac Command+H remains native Hide; history uses Command+Shift+H.

System theme follows CSS prefers-color-scheme live; explicit light/dark preferences
are persisted and applied without restart. Layout uses minimum readable key sizes,
scrolling and a collapsing history drawer. Native decorations, menu integration,
focus indicators, accessible labels and primary-modifier shortcuts respect each OS.

## Packaging and validation

One Cargo package with a library core and a desktop binary. The desktop feature
can be disabled to test domain/persistence code without a display or WebKit.
Native CI builds/tests on Windows MSVC, Linux and both macOS architectures.
Release jobs produce a Windows installer, macOS bundles, Linux archive and
Flatpak, then verify checksum coverage before publishing a tag release.
Migration versions use 0.2.0-alpha.N until the runtime/platform QA matrix is complete.

Tests must exercise the shared reducer, migrations, hostile input and actual
visible UI. A separate `ui-test` feature enables deterministic DOM interaction
inside the real desktop WebView; it is excluded from release builds. Native
keyboard/clipboard checks supplement DOM tests because synthetic DOM events alone
do not verify OS integration. See MIGRATION_AUDIT.md and PLATFORM_SUPPORT.md for
observed evidence and remaining platform verification.
