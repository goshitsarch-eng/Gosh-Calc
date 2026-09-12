# Gosh Calc

A calculator for the COSMIC desktop, built with libcosmic. It has
standard, scientific, and programmer modes, full keyboard support,
and a history drawer that persists across launches.

## AI-assisted development

I use AI tools to speed up development, but I work
architecture-first. I define the architecture, build and review the
implementation, refactor it, and repeat the process as the project
evolves.

I treat AI as a junior developer: useful for implementation and
exploration, but not the final authority. I remain responsible for
the architecture, technical decisions, and quality of the code.

I'm including this notice so you can make an informed choice about
whether AI-assisted software is something you're comfortable using.

## Features

Three modes in the nav bar (persisted across launches):

- **Standard** — arithmetic with correct precedence, chained and
  repeat-equals, context-aware percent, 1/x, x², √.
- **Scientific** — parens (auto-close at `=`), powers and roots
  (x² x³ xʸ y√x √ ∛), log/ln/eˣ/10ˣ, factorial, trig plus
  inverses with a DEG/RAD toggle, π/e constants, EE entry for
  scientific notation, Ans recall.
- **Programmer** — HEX/DEC/OCT/BIN switching with A–F keys,
  all four bases shown at once, AND/OR/XOR/NOT, shifts, modulo,
  exact 64-bit integers.

Every mode has an expression line plus a live result line. The
header button opens a history drawer: newest first, click an
entry to reuse its result, clear button at the bottom, persisted
(cap 100). The copy button (or Ctrl+C) copies the result and
shows a confirmation. Bad input shows `Error` and any digit
starts fresh — the app doesn't crash on it.

## Install

Build and install the Flatpak from this repo:

```sh
flatpak-builder --user --install --force-clean build-dir \
  flatpak/dev.goshapps.calc.yml
flatpak run dev.goshapps.calc
```

You need `flatpak-builder` plus the Freedesktop 25.08 platform
and SDK. The sandbox grants are minimal: Wayland, fallback X11,
IPC, and DRI. No network, no filesystem, no notifications.

## Releases

Prebuilt x86_64 and aarch64 artifacts live on the
[releases page](https://github.com/goshitsarch-eng/Gosh-Calc/releases):
a portable tarball and a single-file Flatpak bundle per architecture,
plus a `SHA256SUMS` checksum file.

```sh
sha256sum -c SHA256SUMS                    # verify downloads first
tar xzf gosh-calc-0.1.0-x86_64.tar.gz      # portable: run ./gosh-calc-*/gosh-calc
flatpak install --user gosh-calc-0.1.0-x86_64.flatpak  # or install the bundle
```

Pick the `-aarch64` files on ARM machines. Maintainers: cutting a
release is tag-driven — see [docs/RELEASING.md](docs/RELEASING.md).

## Use

Pick a mode in the nav bar and type or click. Everything works
from the keyboard without clicking anything first. Mode, angle
unit, and history persist; the HEX/DEC/OCT/BIN selection resets
to DEC on relaunch.

Settings live in your config dir via cosmic-config's file
backend, so the app also runs on non-COSMIC desktops, and
theming follows the settings portal when one is present.

## Keyboard

`0-9` digits (row + numpad) · `a-f` hex digits in programmer HEX ·
`+ - * /` ops · `^` power (XOR in programmer) · `%` percent in
standard/scientific, modulo in programmer · `()` parens ·
`.`/`,` decimal · `!` factorial · `& | < > ~` bitwise ops ·
`p` π in scientific · Enter/`=` evaluate · Backspace delete ·
Delete clear entry · Esc clear all · Ctrl+C / Ctrl+Insert copy ·
`h` or Ctrl+H history.

## Limitations

- No memory (M+/MR/MC) keys and no single-instance mode. Both
  are deliberately deferred (see `docs/design/DECISIONS.md`, D8).
- Unary functions (sin, √, …) apply to the entry immediately,
  so history shows the computed operand rather than the symbolic
  expression.

## Development

```sh
cargo build
cargo test
cargo run
```

`scripts/verify.sh` runs the full gate: fmt, clippy, tests,
desktop/metainfo validation, Flatpak build, and a headless
smoke test. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
checks, Flatpak rebuild notes, and troubleshooting.

After changing `Cargo.lock`, regenerate the vendored Flatpak
sources:

```sh
python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json
```

## Contributing

Bug reports and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for how to set up and verify
changes.

## License

MIT — see [LICENSE](LICENSE).
