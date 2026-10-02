//! The command boundary shared by all UI entry points and integration tests.
use crate::{
    engine::{Base, BinOp, Const, Mode, UnaryOp},
    state::{AppState, Dialog, Theme, WindowState},
};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Command {
    Digit(u8),
    Dot,
    Binary(BinOp),
    Unary(UnaryOp),
    Percent,
    Equals,
    Backspace,
    ClearEntry,
    ClearAll,
    ToggleSign,
    SetBase(Base),
    ToggleAngle,
    LParen,
    RParen,
    Recall(usize),
    ClearHistory,
    SetMode(Mode),
    Ans,
    Exp,
    Constant(Const),
    Copy,
    ToggleHistory,
    ShowDialog(Dialog),
    CloseDialog,
    SetTheme(Theme),
    SetWindow(WindowState),
    DismissNotice,
    Quit,
}

#[derive(Default, Debug)]
pub struct Effect {
    pub persist: bool,
    pub copy: Option<String>,
    pub quit: bool,
}

impl AppState {
    pub fn enabled(&self, command: Command) -> bool {
        match command {
            Command::Digit(d) => {
                if self.calc.mode == Mode::Programmer {
                    self.calc.base.digit_valid(d)
                } else {
                    d < 10
                }
            }
            Command::Dot => self.calc.mode != Mode::Programmer,
            Command::Binary(op) => op.allowed_in(self.calc.mode),
            Command::Unary(op) => op.allowed_in(self.calc.mode),
            Command::ClearHistory | Command::Ans => !self.calc.history.is_empty(),
            Command::Recall(i) => i < self.calc.history.len(),
            _ => true,
        }
    }

    pub fn dispatch(&mut self, command: Command) -> Effect {
        let mut effect = Effect::default();
        if !self.enabled(command) {
            return effect;
        }
        match command {
            Command::Digit(d) => self.calc.input_digit(d),
            Command::Dot => self.calc.input_dot(),
            Command::Binary(op) => self.calc.input_binary(op),
            Command::Unary(op) => self.calc.input_unary(op),
            Command::Percent => self.calc.input_percent(),
            Command::Equals => effect.persist = self.calc.equals().is_some(),
            Command::Backspace => self.calc.backspace(),
            Command::ClearEntry => self.calc.clear_entry(),
            Command::ClearAll => self.calc.clear_all(),
            Command::ToggleSign => self.calc.toggle_sign(),
            Command::SetBase(base) => self.calc.set_base(base),
            Command::ToggleAngle => {
                self.calc.toggle_angle();
                effect.persist = true;
            }
            Command::LParen => self.calc.input_lparen(),
            Command::RParen => self.calc.input_rparen(),
            Command::Recall(i) => self.calc.recall_history(i),
            Command::ClearHistory => {
                self.calc.clear_history();
                effect.persist = true;
            }
            Command::SetMode(mode) => {
                effect.persist = mode != self.calc.mode;
                self.calc.set_mode(mode);
            }
            Command::Ans => self.calc.input_ans(),
            Command::Exp => self.calc.input_exp(),
            Command::Constant(c) => self.calc.input_const(c),
            Command::Copy => effect.copy = Some(self.calc.result_display()),
            Command::ToggleHistory => self.history_open = !self.history_open,
            Command::ShowDialog(dialog) => self.dialog = Some(dialog),
            Command::CloseDialog => self.dialog = None,
            Command::SetTheme(theme) => {
                effect.persist = theme != self.theme;
                self.theme = theme;
            }
            Command::SetWindow(window) => {
                effect.persist = window != self.window;
                self.window = window.bounded();
            }
            Command::DismissNotice => self.notice = None,
            Command::Quit => effect.quit = true,
        }
        effect
    }
}

/// `key` is the modified logical character (DOM KeyboardEvent.key), never the
/// physical/unmodified key. Platform code decides Ctrl versus Command.
pub fn keyboard(key: &str, primary: bool, alt: bool, mode: Mode, base: Base) -> Option<Command> {
    if primary {
        return match key.to_ascii_lowercase().as_str() {
            "c" | "insert" => Some(Command::Copy),
            "h" => Some(Command::ToggleHistory),
            "," => Some(Command::ShowDialog(Dialog::Settings)),
            "q" => Some(Command::Quit),
            "1" => Some(Command::SetMode(Mode::Standard)),
            "2" => Some(Command::SetMode(Mode::Scientific)),
            "3" => Some(Command::SetMode(Mode::Programmer)),
            _ => None,
        };
    }
    if alt {
        return None;
    }
    let command = match key {
        "Enter" | "=" => Command::Equals,
        "Escape" => Command::ClearAll,
        "Delete" => Command::ClearEntry,
        "Backspace" => Command::Backspace,
        "." | "," => Command::Dot,
        "+" => Command::Binary(BinOp::Add),
        "-" => Command::Binary(BinOp::Sub),
        "*" => Command::Binary(BinOp::Mul),
        "/" => Command::Binary(BinOp::Div),
        "%" => Command::Percent,
        "^" => Command::Binary(if mode == Mode::Programmer {
            BinOp::Xor
        } else {
            BinOp::Pow
        }),
        "(" => Command::LParen,
        ")" => Command::RParen,
        "!" => Command::Unary(UnaryOp::Fact),
        "~" => Command::Unary(UnaryOp::Not),
        "&" => Command::Binary(BinOp::And),
        "|" => Command::Binary(BinOp::Or),
        "<" => Command::Binary(BinOp::Shl),
        ">" => Command::Binary(BinOp::Shr),
        "p" | "P" if mode == Mode::Scientific => Command::Constant(Const::Pi),
        "h" | "H" => Command::ToggleHistory,
        "F1" => Command::ShowDialog(Dialog::Shortcuts),
        _ => {
            let digit = key
                .chars()
                .next()
                .filter(|_| key.len() == 1)?
                .to_digit(16)? as u8;
            if digit >= 10 && (mode != Mode::Programmer || base != Base::Hex) {
                return None;
            }
            Command::Digit(digit)
        }
    };
    Some(command)
}
