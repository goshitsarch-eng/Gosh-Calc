# Contributing to Gosh Calc

## Setup

You need a Rust toolchain (stable) and the system libraries for a
libcosmic app. Then:

```sh
git clone https://github.com/goshitsarch-eng/Gosh-Calc.git
cd Gosh-Calc
cargo build
cargo run
```

The first build compiles the whole dependency tree (hundreds of
crates including wgpu), so it takes a while. Later builds are
incremental. No COSMIC session is required to run it.

## Checks

Run the suite and lints:

```sh
cargo test            # 34 unit + 37 integration tests
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```

For the full gate — fmt, clippy, tests, desktop/metainfo
validation, Flatpak build, headless smoke test — run:

```sh
scripts/verify.sh
```

Run this before opening a pull request. It skips the Flatpak
stages with a warning if `flatpak-builder` isn't installed.

## Code layout

- `src/engine.rs` — the calculator itself: tokens, evaluation,
  formatting, history. Pure Rust, no libcosmic imports. Keep it
  that way so tests can drive it without a GUI.
- `src/main.rs` — the libcosmic shell: `Message`, key mapping,
  view, keypads, history drawer. Engine-bound messages go
  through `reduce()`; clipboard/drawer/keyboard plumbing stays
  in `update()`.
- `src/config.rs` — persistence. Persisted state is exactly
  mode, angle unit, and history, saved only when one of those
  changes (`needs_save` in `main.rs`). Don't add per-keystroke
  writes.
- `src/i18n.rs` + `i18n/en/gosh_calc.ftl` — Fluent strings.
  User-visible chrome goes through `fl!()`; keypad symbols
  stay literal.
- `tests/integration.rs` — end-to-end flows through the same
  engine calls the UI drives.

Design context lives in `docs/design/` (decisions, UX spec,
architecture, packaging). `docs/audit/` is the record of a past
hardening pass — history, not a task list.

## Flatpak

The manifest is `flatpak/dev.goshapps.calc.yml` (Freedesktop
25.08, rust-stable SDK extension, offline vendored build).
Rebuild and run it with:

```sh
flatpak-builder --user --install --force-clean build-dir \
  flatpak/dev.goshapps.calc.yml
flatpak run dev.goshapps.calc
```

After any `Cargo.lock` change, regenerate the vendored sources
or the offline build breaks:

```sh
python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json
```

Finish-args stay minimal (Wayland, fallback X11, IPC, DRI).
Don't add permissions the app doesn't need.

## Troubleshooting

**Flatpak build fails with `failed to access mountpoint`.**
A stale `rofiles-fuse` mount plus FUSE restrictions on the host.
`verify.sh` already passes `--disable-rofiles-fuse` for this;
use the same flag on manual builds.

**Offline Flatpak build complains about missing sources.**
`flatpak/cargo-sources.json` is stale. Regenerate it with the
command above and rebuild.

**`scripts/smoke.sh` exits with `no display server available`.**
It needs a Wayland session, `weston`, or an X11 `DISPLAY` to
launch the app under. Install weston or run it from a desktop
session.

**First `cargo build` seems stuck.**
It's compiling ~600 crates. Give it time; check with
`cargo build -v` if you want proof of progress.
