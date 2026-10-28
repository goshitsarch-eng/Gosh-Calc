# Golden corpus provenance

`tests/golden/*` and `tests/fixtures/rust-0.2/*` were recorded from the **Rust
(Dioxus) release of Gosh Calc**, commit `82d3a49` (0.2.0-alpha.1). They pin the
behaviour of that implementation so the Godot port can be checked against it
without Rust being present.

* `requests.jsonl.gz` / `expected.jsonl.gz`: 4,180 request lines. A request is
  a command sequence (`{"seq": [...]}`, optionally with preloaded `history`) or
  a keyboard probe (`{"key": ...}`). `expected` holds, for every step, a
  canonical string of the *entire* application state (display, expression,
  entry, error, base readout, mode/base/angle, effects, dialog/theme/window and
  a hash of the history). Format: see `tests/support/codec.gd`.
* `parse_cases.tsv.gz`: decimal strings with the correctly rounded IEEE bits
  (Python `float()`); `fmt_cases.tsv.gz`: IEEE bits with the Rust `fmt_f64`
  output, including exact round-half-even ties.
* `tests/fixtures/rust-0.2/*/settings.json` were written by the Rust
  `Store::save`; Godot must load them and re-save byte-identically.

## Regenerating (needs Rust)

1. `git checkout 82d3a49` into a scratch directory; keep only `src/{engine,
   commands,state,persistence}.rs` and `lib.rs` plus a Cargo.toml depending on
   `serde`, `serde_json`, `ron`, `directories`, `log`.
2. Copy `oracle.rs` and `settings_tool.rs` into `src/bin/`; `cargo build`.
3. `python3 gen_corpus.py <seed> <n> corpus.jsonl` and `python3 gen_extra.py`
   produce request files; `oracle < corpus.jsonl > expected.jsonl`.
4. Replay with `godot --headless -s tests/diff_runner.gd -- corpus.jsonl expected.jsonl`.

The port was additionally checked against ~2.6 million freshly generated steps
(seeds 1-5 plus the extra edge corpus) with zero mismatches; only the 166k-step
subset above is stored.
