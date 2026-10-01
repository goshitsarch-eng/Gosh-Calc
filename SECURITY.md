# Security and dependency review

The calculator performs no network requests or external commands. History is
rendered as text, never evaluated JavaScript. JSON/RON reads are bounded to 1 MiB,
history to 100 records/256 bytes per field, and expression tokens/nesting are
bounded. Saving uses a same-directory unique temporary file, sync and replacement;
corrupt configuration and legacy imports retain backups. Future schemas disable
saving. Application Rust contains no unsafe code.

`cargo audit` was run on 2026-10-01. Inspect its warnings as well as the
vulnerability count. Dioxus Desktop's Linux GTK3 host fixes GLib's API line at
0.18.5. RUSTSEC-2024-0429 is fixed by the upstream two-line backport in vendor/glib;
forward/reverse Unicode iteration is tested in optimized builds. See
vendor/README.md for the source checksum and upstream patch. An audit version
match may still report that advisory because the backport retains the upstream
version. Do not replace the fix with a blanket advisory ignore.

Transitive `fxhash`, `paste` and `proc-macro-error` have unmaintained advisories.
`rand` 0.7.3 is used by the WebView's build-time selector generator and has
RUSTSEC-2026-0097 concerning a custom logger that recursively uses RNG. This
application neither implements that logger nor uses that rand version for
application randomness. These are upstream dependency liabilities to revisit
with future Dioxus/WebView releases, not silently suppressed audit results.

Dioxus 0.7.10 references Wry inspector methods even with its development tools
feature disabled. A narrow direct Wry feature enables compilation; production
WebViews leave inspection disabled and do not include Dioxus's development server.

Cargo and Flatpak archive checksum verification, Debian package signatures, TLS
and WebKit sandboxing stay enabled. Flatpak production permissions are limited
to display sockets, IPC and graphics. UI QA uses a separate build feature and a
narrow temporary-directory grant for collecting its outcome. Neither ships as
extra application functionality. Upstream unsafe code remains within native
integration dependencies; the isolated backport repairs its C out-pointer use.
