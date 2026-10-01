# GLib security backport

`glib/` is the crates.io glib 0.18.5 source archive (MIT), originally verified by
Cargo against SHA-256 `233daaf6e83ae6a12a52055f568f9d7cf4671dabb78ff9560ab6da230ce00ee5`.
Keep its LICENSE. Dioxus Desktop's GTK3/WebKit host currently requires the 0.18
API, so upgrading it directly to 0.20 is incompatible with the upstream stack.

The only behavioral change is the upstream RUSTSEC-2024-0429 fix in
`src/variant_iter.rs`: declare the C out-argument pointer mutable and pass
`&mut p` to `g_variant_get_child`. Reference:
https://github.com/gtk-rs/gtk-rs-core/pull/1343

`tests/glib_regression.rs` exercises forward and double-ended string iteration,
including nth/last, on Unicode data. Run in release mode too: the original bug
can be optimized into a null dereference. The path patch is included in Flatpak
sources. Remove this copy when Dioxus supports a compatible fixed upstream GLib.
Upstream TODOs inside this vendored dependency are not application placeholders.
