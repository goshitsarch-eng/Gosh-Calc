use super::Dispatch;
use dioxus::prelude::*;
use gosh_calc::{
    commands::Command as C,
    engine::{BinOp as B, Const, Mode, UnaryOp as U},
};

#[derive(Clone, Debug, PartialEq)]
pub struct Key {
    pub label: &'static str,
    pub name: &'static str,
    pub command: C,
}
fn key(label: &'static str, name: &'static str, command: C) -> Key {
    Key {
        label,
        name,
        command,
    }
}
fn digit(d: u8) -> Key {
    let label = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F",
    ][d as usize];
    key(label, label, C::Digit(d))
}
pub fn keys(mode: Mode) -> Vec<Key> {
    let clear = || {
        vec![
            key("CE", "Clear entry", C::ClearEntry),
            key("C", "Clear calculation", C::ClearAll),
            key("⌫", "Backspace", C::Backspace),
        ]
    };
    let standard = vec![
        key("%", "Percent", C::Percent),
        clear()[0].clone(),
        clear()[1].clone(),
        clear()[2].clone(),
        key("1/x", "Reciprocal", C::Unary(U::Recip)),
        key("x²", "Square", C::Unary(U::Square)),
        key("√", "Square root", C::Unary(U::Sqrt)),
        key("÷", "Divide", C::Binary(B::Div)),
        digit(7),
        digit(8),
        digit(9),
        key("×", "Multiply", C::Binary(B::Mul)),
        digit(4),
        digit(5),
        digit(6),
        key("−", "Subtract", C::Binary(B::Sub)),
        digit(1),
        digit(2),
        digit(3),
        key("+", "Add", C::Binary(B::Add)),
        key("±", "Toggle sign", C::ToggleSign),
        digit(0),
        key(".", "Decimal point", C::Dot),
        key("=", "Equals", C::Equals),
    ];
    match mode {
        Mode::Standard => standard,
        Mode::Scientific => {
            let functions = vec![
                key("x²", "Square", C::Unary(U::Square)),
                key("x³", "Cube", C::Unary(U::Cube)),
                key("xʸ", "Power", C::Binary(B::Pow)),
                key("y√x", "Nth root", C::Binary(B::YRoot)),
                key("√", "Square root", C::Unary(U::Sqrt)),
                key("∛", "Cube root", C::Unary(U::Cbrt)),
                key("1/x", "Reciprocal", C::Unary(U::Recip)),
                key("x!", "Factorial", C::Unary(U::Fact)),
                key("sin", "Sine", C::Unary(U::Sin)),
                key("cos", "Cosine", C::Unary(U::Cos)),
                key("tan", "Tangent", C::Unary(U::Tan)),
                key("ln", "Natural logarithm", C::Unary(U::Ln)),
                key("sin⁻¹", "Inverse sine", C::Unary(U::Asin)),
                key("cos⁻¹", "Inverse cosine", C::Unary(U::Acos)),
                key("tan⁻¹", "Inverse tangent", C::Unary(U::Atan)),
                key("log", "Logarithm", C::Unary(U::Log10)),
                key("eˣ", "Exponential", C::Unary(U::Exp)),
                key("10ˣ", "Power of ten", C::Unary(U::Pow10)),
                key("π", "Pi", C::Constant(Const::Pi)),
                key("e", "Euler's number", C::Constant(Const::E)),
                key("DEG/RAD", "Toggle angle unit", C::ToggleAngle),
                key("|x|", "Absolute value", C::Unary(U::Abs)),
                key("EE", "Scientific notation", C::Exp),
                key("Ans", "Last answer", C::Ans),
            ];
            let numeric = [
                clear()[0].clone(),
                clear()[1].clone(),
                clear()[2].clone(),
                standard[7].clone(),
                digit(7),
                digit(8),
                digit(9),
                standard[11].clone(),
                digit(4),
                digit(5),
                digit(6),
                standard[15].clone(),
                digit(1),
                digit(2),
                digit(3),
                standard[19].clone(),
                standard[20].clone(),
                digit(0),
                standard[22].clone(),
                standard[23].clone(),
                key("(", "Open parenthesis", C::LParen),
                key(")", "Close parenthesis", C::RParen),
                key("%", "Percent", C::Percent),
            ];
            // Function and numeric panels remain four-column groups when narrow.
            functions.into_iter().chain(numeric).collect()
        }
        Mode::Programmer => vec![
            digit(10),
            digit(11),
            digit(12),
            digit(13),
            digit(14),
            digit(15),
            key("<<", "Shift left", C::Binary(B::Shl)),
            key(">>", "Shift right", C::Binary(B::Shr)),
            key("AND", "Bitwise AND", C::Binary(B::And)),
            key("OR", "Bitwise OR", C::Binary(B::Or)),
            key("XOR", "Bitwise XOR", C::Binary(B::Xor)),
            key("NOT", "Bitwise NOT", C::Unary(U::Not)),
            key("(", "Open parenthesis", C::LParen),
            key(")", "Close parenthesis", C::RParen),
            key("mod", "Modulo", C::Percent),
            clear()[0].clone(),
            clear()[1].clone(),
            clear()[2].clone(),
            digit(7),
            digit(8),
            digit(9),
            key("±", "Toggle sign", C::ToggleSign),
            standard[7].clone(),
            standard[11].clone(),
            digit(4),
            digit(5),
            digit(6),
            digit(0),
            standard[15].clone(),
            standard[19].clone(),
            digit(1),
            digit(2),
            digit(3),
            key("Ans", "Last answer", C::Ans),
            key("=", "Equals", C::Equals),
        ],
    }
}

#[component]
pub fn Keypad() -> Element {
    let dispatch = use_context::<Dispatch>();
    let state = dispatch.model.read();
    let mode = state.calc.mode;
    let buttons = keys(mode);
    if mode == Mode::Scientific {
        return rsx! { div { class: "keypad scientific", "aria-label": "Scientific keypad",
            KeyGrid { buttons: buttons[..24].to_vec(), class: "scientific-functions" }
            KeyGrid { buttons: buttons[24..].to_vec(), class: "scientific-numeric" }
        }};
    }
    rsx! { KeyGrid { buttons, class: if mode == Mode::Standard { "keypad standard" } else { "keypad programmer" } } }
}

#[component]
fn KeyGrid(buttons: Vec<Key>, class: String) -> Element {
    let dispatch = use_context::<Dispatch>();
    let state = dispatch.model.read();
    rsx! {
        div { class, "aria-label": "Calculator keypad",
            for (index, key) in buttons.into_iter().enumerate() {
                button {
                    key: "{index}",
                    class: match key.command { C::Equals => "key equals", C::Digit(_) => "key digit", _ => "key function" },
                    "data-command": "{key.name}",
                    "aria-label": key.name,
                    title: key.name,
                    disabled: !state.enabled(key.command),
                    onclick: move |_| dispatch.run(key.command),
                    "{key.label}"
                }
            }
        }
    }
}
