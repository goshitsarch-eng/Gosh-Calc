# Gosh Calc

A calculator for the COSMIC desktop, built with libcosmic.

Three modes (nav bar, persisted across launches):

- **Standard** — arithmetic with correct precedence, chained and
  repeat-equals, context-aware percent, 1/x, x², √.
- **Scientific** — parens (auto-close at `=`), powers/roots
  (x² x³ xʸ y√x √ ∛), log/ln/eˣ/10ˣ, factorial, trig + inverses with
  DEG/RAD toggle, π/e constants, EE scientific entry, Ans recall.
- **Programmer** — HEX/DEC/OCT/BIN switching with A–F keys,
  simultaneous four-base readout, AND/OR/XOR/NOT, shifts, modulo,
  exact 64-bit two's-complement integers.

History drawer (header button): newest-first list, click to recall,
clear button, persisted (cap 100). Copy button + Ctrl+C copies the
result with a toast confirmation. Errors show `Error` and any digit
restarts fresh — the app never panics on bad input.

## Build

```sh
cargo build
cargo test
```

Pinned libcosmic rev (see `Cargo.toml`) + `Cargo.lock`; release
profile uses thin LTO.

## Run

```sh
cargo run
```

No COSMIC session required: settings persist via the cosmic-config
file backend and theming follows the settings portal when present.

## Keyboard

`0-9` digits (row + numpad) · `a-f` hex digits in programmer HEX ·
`+ - * /` ops · `^` power (XOR in programmer) · `%` percent/modulo ·
`()` parens · `.`/`,` decimal · `!` factorial · `& | < > ~` bitwise ·
`p` π (scientific) · Enter/`=` evaluate · Backspace delete ·
Delete clear entry · Esc clear all · Ctrl+C / Ctrl+Insert copy ·
`h` or Ctrl+H history.

## Flatpak

```sh
scripts/verify.sh   # fmt + clippy + test + flatpak build + smoke
```

Finish-args are minimal (wayland, fallback-x11, ipc, dri). Regenerate
`flatpak/cargo-sources.json` after `Cargo.lock` changes:

```sh
python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json
```

## Known limitations

No memory (M+/MR/MC) keys and no single-instance — deferred by design
(see `docs/design/DECISIONS.md` D8). The numeric base (HEX/…) resets
to DEC on relaunch; mode, angle unit, and history persist.
