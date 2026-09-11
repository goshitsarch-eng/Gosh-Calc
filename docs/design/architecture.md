# Gosh-Calc Architecture

Owner: architecture teammate. Covers the state model, engine, config,
and how they map onto libcosmic's `Application` model.

## Module layout

```
src/main.rs    — Application impl: Message, init, update, view,
                 subscription, header_end, context_drawer
src/engine.rs  — pure-Rust calc engine (no libcosmic imports)
src/config.rs  — persisted settings via cosmic-config
src/i18n.rs    — Fluent localizer setup (i18n-embed)
i18n/en/gosh_calc.ftl — English strings
tests/         — integration tests driving messages through the app
```

The engine never imports libcosmic. `main.rs` translates `Message`s
into engine calls and formats engine output for the view. All
message-handling logic lives in a free function
`reduce(state: &mut CalcState, msg: &InputMsg)` so tests can drive the
whole app state machine without constructing a `cosmic::Core`.

## libcosmic Application mapping

- `App` holds: `core: Core`, `nav_model: nav_bar::Model`,
  `state: CalcState`, `config: AppConfig`, `config_store: Config`.
- `init` loads config (mode, angle unit, history) and builds the nav
  model (Standard / Scientific / Programmer).
- `on_nav_select` maps nav ids -> `Mode`.
- `header_end` -> history drawer toggle button.
- `context_drawer` -> history list when `show_context` is set.
- `subscription` -> `iced::event::listen_with` for keyboard input.
- Messages: `Digit`, `Dot`, `Binary(BinOp)`, `Unary(UnaryOp)`,
  `Percent`, `Equals`, `Backspace`, `ClearEntry`, `ClearAll`,
  `ToggleSign`, `SetMode`, `SetBase`, `ToggleAngle`, `Constant`,
  `RecallHistory(usize)`, `ClearHistory`, `CopyResult`, `ToggleContext`,
  `Key(KeyBind)`, `Surface`.

## Engine model

Immediate-execution calculator with a token list, not a line parser.

```
CalcState {
  mode: Mode,               // Standard | Scientific | Programmer
  angle: AngleUnit,         // Deg | Rad
  base: Base,               // Hex | Dec | Oct | Bin
  expr: Vec<Token>,         // committed tokens
  entry: String,            // raw operand text being typed (current base)
  error: Option<CalcError>,
  last_binop: Option<(BinOp, Value)>,  // for repeat-equals
  fresh: bool,              // entry starts a new number (post-=, post-op)
}
```

`Value = Float(f64) | Int(i64)` — Float for standard/scientific, Int
(exact 64-bit two's complement) for programmer. Mixing promotes to
Float; programmer-only ops require Int or get a truncated conversion.

### Evaluation

`expr` + pending `entry` evaluate via precedence climbing:

- precedence 5: `x^y`, `y√x` (right-assoc)
- precedence 4: `×`, `÷`, `mod`
- precedence 3: `+`, `−`
- precedence 2: `<<`, `>>`
- precedence 1: `&`
- precedence 0: `xor`, `|`

Parentheses wrap sub-expressions; unclosed parens auto-close at `=`.
Pressing `=` evaluates the whole token list, pushes
`expression = result` to history, stores `(last_op, last_operand)` for
repeat-`=` (`2+3=` → 5, `=` → 8).

Unary functions (x², x³, √, ∛, 1/x, x!, sin/cos/tan + inverses, ln,
log, eˣ, 10ˣ, NOT) apply to the current entry value immediately; the
entry becomes the formatted result. This is iOS/GNOME convention and
keeps `entry` a plain string.

Percent is context-aware: `a + b%` computes `a * b/100` (b% of the
running context) for `+`/`−`; `a × b%` and `a ÷ b%` use `b/100`. With no
context, `b%` = `b/100`. In programmer mode the `%` key is modulo.

### Numeric representation

f64 for the float domain, displayed through `fmt_f64`: 12 significant
digits, trailing zeros trimmed, `e`-notation outside
1e-9 < |v| < 1e16. `0.1 + 0.2` displays `0.3` (display-level rounding
to 12 sig digits absorbs binary float artifacts — see DECISIONS.md).

Programmer mode uses i64: `i64::from_str_radix` parses in the active
base (hex input parsed as u64 bits for two's-complement negatives).
Bitwise ops and shifts use wrapping semantics; hex display renders the
u64 bit pattern uppercase. Division truncates toward zero (integer
division). Values above 2^53 entered as hex stay exact because they
never pass through f64.

### Errors

`CalcError`: `DivByZero`, `Overflow`, `Domain`, `InvalidExpr`,
`OutOfRange` (programmer parse). Error state freezes the entry; the
next digit or `C` starts fresh. Errors never panic: every evaluator
path returns `Result`.

## Persistence

`cosmic-config` (`Config::new(APP_ID, 1)`), file backend — `dbus-config`
feature is off so no COSMIC session services are required:

- `mode` (string), `angle` (deg/rad), `history` (Vec of (expr, result),
  cap 100).

Writes go through a `transaction()` batch on each state change that
matters (mode switch, equals, clear-history, angle toggle). Load once in
`init`; failures fall back to defaults.

## i18n

`i18n-embed` + `fluent-system` + `i18n-embed-fl`; strings in
`i18n/en/gosh_calc.ftl`, macro `fl!()`. Localizer initialized in `main`
before `app::run`, matching the pattern used by cosmic-edit.
