# Feature matrix — Gosh Calc

Status key: working / partial / missing. Every row traced
UI → Message → update/reduce → engine → visible feedback.

| Feature | Exposed | Expected | Path | Status | Tests | Verified |
|---|---|---|---|---|---|---|
| Digits 0-9 | keypad, keyboard incl numpad | append to entry, base-filtered | `Digit` → `input_digit` | working | unit + integration | cargo test |
| Decimal point | `.` key, `./,` keys | single dot per entry, no-op in programmer | `Dot` → `input_dot` | working | unit | cargo test |
| Sign toggle | `±` key | prefix `-`, programmer wraps-negate | `ToggleSign` → `toggle_sign` | working | unit | cargo test |
| + − × ÷ precedence | keypad + keyboard | 2+3×4=14, right-assoc `^` | `Binary` → `input_binary` → `eval_tokens` | working | precedence, repeat | cargo test |
| Repeat-equals | `=` repeatedly | 2+3=5,==8,==11 | `Equals` → `equals` + `repeat` slot | working | chained_and_repeat | cargo test |
| Percent | `%` key + `%` key | 100+10%=110, 200×10%=20 | `Percent` → `input_percent` | working | percent_semantics | cargo test |
| CE / C / Del | keypad + Delete/Esc/Backspace | clear entry / all / one char | `ClearEntry/ClearAll/Backspace` | working | backspace_and_clear | cargo test |
| 1/x, x², √ (standard) | standard pad row 2 | immediate unary on entry | `Unary` → `input_unary` | working | scientific_functions | cargo test |
| Powers/roots sci | scientific pad | x² x³ xʸ y√x √ ∛ | `Unary/Binary` | working | unit | cargo test |
| log ln eˣ 10ˣ x! | scientific pad | domain errors on bad input | `input_unary` | working | factorial_domain | cargo test |
| Trig + inverses | scientific pad | DEG/RAD aware, ε-snapped | `apply_unary` | working | trig_degrees_radians | cargo test |
| DEG/RAD toggle | angle key + caption | flips unit, persists | `ToggleAngle` | working | flow_angle_toggle | cargo test |
| π / e constants | `π`,`e` keys, `p` key | entry := constant | `Constant` → `input_const` | working | constants_and_overflow | cargo test |
| EE / Ans | scientific pad keys | `5e3` notation, last-result recall | `Exp/Ans` | working | — (no direct test) | code read; ADD TEST |
| Parens + auto-close | scientific/programmer pads, `()` keys | `(2+3)*4=20`, unclosed auto-close | `LParen/RParen` | working | parens | cargo test |
| Base switch HEX/DEC/OCT/BIN | display selector row | reinterpret entry in new base | `SetBase` → `set_base` | working | programmer_bases | cargo test |
| Four-base readout | programmer display | HEX/DEC/OCT/BIN of current value | `base_readout` | working | base_readout | cargo test |
| A–F hex digits | hex row, `a-f` keys | disabled unless HEX | `Digit(10-15)` + `digit_valid` | working | digit_filtered_by_base | cargo test |
| AND OR XOR NOT << >> mod | programmer pad, `&\|^<>~!` keys | wrapping i64 semantics | `apply_binary` int path | working | programmer_bitwise | cargo test |
| Copy result | copy icon button, Ctrl+C | clipboard := result + feedback | `CopyResult` → clipboard write | partial — copies, NO feedback | none | code read; ADD TOAST+TEST |
| History drawer | header toggle, Ctrl+H | list expr=result newest-first | `ToggleContext` + drawer view | working | flow_history_clear | cargo test |
| History recall | entry rows | result → entry | `Recall(i)` → `recall_history` | working | flow_calculate_and_recall | cargo test |
| History clear | drawer footer | empties + persists | `ClearHistory` | working (button enabled when empty — FIX) | flow_history_clear | cargo test |
| History persistence | automatic | mode/angle/history survive restart | config load/save | partial — works, saves on every keystroke (FIX) | none (needs test) | code read |
| Error display | result line | "Error", digit recovers | `error` slot | partial — English-only hardcode (FIX) | flow_error_recovery | cargo test |
| Keyboard map | global subscription | per ux spec | `key_message` | partial — missing Ctrl+Ins, plain `h` (FIX) | none | code read |
| Light/dark theme | automatic | COSMIC theme widgets | theme::Button/Text | working | — (visual) | manual pass |
| About/settings pages | — | none specified | — | missing (not specified; intentional) | — | DECISIONS |

## UI without implementation

None found: every button/key/drawer action traces to engine code.
Closest items: copy lacks feedback (backend works, feedback missing);
error string lacks localization (backend works, i18n missing).

## Implementation without accessible UI

- `BinOp::Mod` has no dedicated key (reached via `%` in programmer
  mode → intended, documented).
- `UnaryOp::{Cube,Cbrt,Fact,Abs}` allowed in Standard via keyboard
  `!` etc. but only some have standard-pad buttons → intended
  (keyboard superset), documented here.
- `fl!("copied")`, `fl!("error")` strings exist without call sites →
  wire them (FIX) rather than leave dead.
