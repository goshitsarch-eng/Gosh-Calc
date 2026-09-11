# Design Decisions

Recorded per the disagreement-resolution rules. Newest last.

## D1: f64 + display rounding, not a decimal-arithmetic library

Question: numeric domain for the float path — f64 vs. rust_decimal /
arbitrary-precision.

Options: (a) f64 everywhere with 12-significant-digit display rounding;
(b) rust_decimal for + - * / and f64 for transcendentals; (c) MPFR-class
library.

Choice: (a).

Why: transcendentals (sin, ln, x^y) must be f64 regardless, so (b)
still leaks artifacts through any mixed expression; its extra exactness
applies only to pure +-*/ chains, which (a) already renders correctly at
the display layer (0.1+0.2 shows 0.3). (c) is a C dependency that
complicates the Flatpak. Option (a) matches what shipping calculators
(GNOME, iOS) effectively present. Known consequence: stored precision
is f64 (~15-16 digits); display intentionally rounds to 12.

## D2: dbus-config disabled; config via cosmic-config file backend

Question: how to persist settings in a way that also works in the
Flatpak sandbox on non-COSMIC desktops.

Choice: libcosmic without `dbus-config`; `cosmic-config` falls back to
files under XDG config.

Why: spec requires the app to work outside the COSMIC desktop;
dbus-config needs cosmic-settings-daemon. File backend needs no session
services. Priority order: works-in-sandbox beats COSMIC-convention
purity, and file config is still the same cosmic-config API.

## D3: nav_bar for mode switching

Question: mode switcher — nav bar vs. header segmented control.

Choice: `nav_bar::Model` with three pages.

Why: it is the canonical COSMIC pattern for app sections, gives the
standard collapse behavior and styling, and integrates with
`Application::nav_model`/`on_nav_select`. A segmented control would be
a custom pattern. COSMIC convention wins at equal cost.

## D4: percent is context-aware (GNOME semantics)

Question: `a + b%` meaning — literal b/100 vs. b% of a.

Choice: GNOME convention: +,- -> a*b/100; x,/ -> b/100.

Why: it is what users of a desktop calculator expect (tip/discount math)
and matches the dominant Linux calculator. Documented because cheap
four-function calculators do the literal thing.

## D5: unary functions apply to the entry immediately

Question: keep `sin(30)` as a symbolic token vs. apply at once.

Choice: apply at once; entry becomes the formatted result.

Why: keeps `entry` a plain string the user can keep editing/backspacing,
matching iOS/GNOME immediate-eval feel. Trade-off recorded: history
shows the evaluated operand (e.g. `2 + 0.5`), not `2 + sin(30)`. If a
future pass wants symbolic display, tokens already support wrapping —
revisit only if Phase 3 flags it as a UX defect.

## D6: programmer mode is i64 (exact 64-bit), not f64

Question: integer domain — f64 (lossy past 2^53) vs. i64.

Choice: `Value::Int(i64)`; bitwise/shift/div use i64 ops; hex display
is the u64 bit pattern.

Why: spec requires faithful hex display and bitwise ops; f64 silently
drops low bits above 2^53 which would corrupt e.g. NOT of a 64-bit
value. Cost is a small Value enum; worth it for correctness (top
priority in the tie-break order).

## D7: `^` key is mode-scoped

Question: `^` on the keyboard — power or XOR.

Choice: XOR in programmer mode, x^y elsewhere — same convention as
hardware calculators and Windows Calculator.

## D8: `single-instance` and memory functions skipped

Choice: no single-instance, no M+/MR/MC memory row.

Why: neither is in the spec; single-instance adds zbus blocking API
surface inside the sandbox for marginal benefit on a calculator; memory
keys are a candidate fast-follow recorded here rather than silently
absent.

## D9: patched `flatpak-cargo-generator.py` for submodule fetch

Question: the generator's `git fetch origin <commit>` failed on
libcosmic because fetch recursed into the `iced` submodule whose pinned
commit is not servable by its remote (`not our ref`).

Options considered: vendor the git repos by hand; patch the generator.

Choice: patched the vendored generator: `fetch --no-recurse-submodules`
plus a tolerated `git submodule update` failure. Submodule contents are
never cargo dependencies — cargo-sources only needs `Cargo.toml` files
of workspace members, which live in the parent repo.

Note: flatpak-builder itself *can* fetch the submodule (it fetches the
full repo including all refs, so the pinned commit resolves), so the
patch is only needed on the generation side.

## D10: `--disable-rofiles-fuse` in local flatpak builds

A stale `rofiles-fuse` mount + FUSE restrictions on this host made
`flatpak-builder` fail with `failed to access mountpoint`. All build
invocations use `--disable-rofiles-fuse`; it only disables the
hardlink safety layer, not correctness of the output.

## D11: vendored cargo config lands via `.cargo/config.toml`

`flatpak-cargo-generator` emits `cargo/config` + `cargo/vendor`. The
manifest copies the config to `.cargo/config.toml` in the build root so
`directory = "cargo/vendor"` resolves correctly, and sets `CARGO_HOME`
to a separate `cargo-home` dir so the vendored config is not
misinterpreted as a home config.
