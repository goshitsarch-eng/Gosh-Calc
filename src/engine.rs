// Copyright (c) 2026 goshitsarch-eng
// SPDX-License-Identifier: MIT

//! Calculator engine: pure Rust, no libcosmic imports.
//!
//! Immediate-execution model: the user builds a token list
//! (`expr`) plus a raw `entry` string for the operand being typed.
//! `=` evaluates the whole token list with correct precedence.

use std::fmt;

const MAX_ENTRY_LEN: usize = 32;
const MAX_HISTORY: usize = 100;

#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Mode {
    Standard,
    Scientific,
    Programmer,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum AngleUnit {
    Deg,
    Rad,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Base {
    Hex,
    Dec,
    Oct,
    Bin,
}

impl Base {
    pub fn radix(self) -> u32 {
        match self {
            Base::Hex => 16,
            Base::Dec => 10,
            Base::Oct => 8,
            Base::Bin => 2,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Base::Hex => "HEX",
            Base::Dec => "DEC",
            Base::Oct => "OCT",
            Base::Bin => "BIN",
        }
    }

    pub fn digit_valid(self, d: u8) -> bool {
        d < self.radix() as u8
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    YRoot,
    Shl,
    Shr,
    And,
    Or,
    Xor,
}

impl BinOp {
    /// Higher binds tighter. C-like ordering for bitwise ops.
    fn precedence(self) -> u8 {
        match self {
            BinOp::Pow | BinOp::YRoot => 5,
            BinOp::Mul | BinOp::Div | BinOp::Mod => 4,
            BinOp::Add | BinOp::Sub => 3,
            BinOp::Shl | BinOp::Shr => 2,
            BinOp::And => 1,
            BinOp::Xor | BinOp::Or => 0,
        }
    }

    /// Only `Pow`/`YRoot` are right-associative (2^3^2 = 2^9).
    fn right_assoc(self) -> bool {
        matches!(self, BinOp::Pow | BinOp::YRoot)
    }

    pub fn symbol(self) -> &'static str {
        match self {
            BinOp::Add => "+",
            BinOp::Sub => "−",
            BinOp::Mul => "×",
            BinOp::Div => "÷",
            BinOp::Mod => "mod",
            BinOp::Pow => "^",
            BinOp::YRoot => "y√",
            BinOp::Shl => "<<",
            BinOp::Shr => ">>",
            BinOp::And => "&",
            BinOp::Or => "|",
            BinOp::Xor => "xor",
        }
    }

    pub fn allowed_in(self, mode: Mode) -> bool {
        match self {
            BinOp::Mod | BinOp::Shl | BinOp::Shr | BinOp::And | BinOp::Or | BinOp::Xor => {
                mode == Mode::Programmer
            }
            _ => true,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UnaryOp {
    Square,
    Cube,
    Sqrt,
    Cbrt,
    Recip,
    Fact,
    Sin,
    Cos,
    Tan,
    Asin,
    Acos,
    Atan,
    Ln,
    Log10,
    Exp,
    Pow10,
    Not,
    Abs,
}

impl UnaryOp {
    pub fn symbol(self) -> &'static str {
        match self {
            UnaryOp::Square => "x²",
            UnaryOp::Cube => "x³",
            UnaryOp::Sqrt => "√",
            UnaryOp::Cbrt => "∛",
            UnaryOp::Recip => "1/x",
            UnaryOp::Fact => "x!",
            UnaryOp::Sin => "sin",
            UnaryOp::Cos => "cos",
            UnaryOp::Tan => "tan",
            UnaryOp::Asin => "sin⁻¹",
            UnaryOp::Acos => "cos⁻¹",
            UnaryOp::Atan => "tan⁻¹",
            UnaryOp::Ln => "ln",
            UnaryOp::Log10 => "log",
            UnaryOp::Exp => "eˣ",
            UnaryOp::Pow10 => "10ˣ",
            UnaryOp::Not => "~",
            UnaryOp::Abs => "|x|",
        }
    }

    pub fn allowed_in(self, mode: Mode) -> bool {
        match self {
            UnaryOp::Not => mode == Mode::Programmer,
            UnaryOp::Square | UnaryOp::Cube | UnaryOp::Sqrt | UnaryOp::Cbrt | UnaryOp::Recip
            | UnaryOp::Fact | UnaryOp::Abs => mode != Mode::Programmer,
            _ => mode == Mode::Scientific,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Const {
    Pi,
    E,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CalcError {
    DivByZero,
    Overflow,
    Domain,
    InvalidExpr,
    OutOfRange,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            CalcError::DivByZero => "Division by zero",
            CalcError::Overflow => "Overflow",
            CalcError::Domain => "Domain error",
            CalcError::InvalidExpr => "Invalid expression",
            CalcError::OutOfRange => "Value out of range",
        })
    }
}

/// Numeric value: exact i64 in programmer mode, f64 elsewhere.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Value {
    F(f64),
    I(i64),
}

impl Value {
    fn as_f64(self) -> f64 {
        match self {
            Value::F(v) => v,
            Value::I(v) => v as f64,
        }
    }

    fn as_i64(self) -> i64 {
        match self {
            Value::I(v) => v,
            Value::F(v) => v as i64,
        }
    }

    fn is_int(self) -> bool {
        matches!(self, Value::I(_))
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Token {
    Val(Value),
    Op(BinOp),
    LParen,
    RParen,
}

/// One completed calculation for the history panel.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct HistoryEntry {
    pub expr: String,
    pub result: String,
}

#[derive(Clone, Debug)]
pub struct CalcState {
    pub mode: Mode,
    pub angle: AngleUnit,
    pub base: Base,
    pub error: Option<CalcError>,
    expr: Vec<Token>,
    entry: String,
    /// Last binary op + right operand, for repeat `=`.
    repeat: Option<(BinOp, Value)>,
    /// Entry starts fresh on next digit (post-op, post-=).
    fresh: bool,
    /// Set right after a successful `=` while `entry` holds the result.
    evaluated: bool,
    pub history: Vec<HistoryEntry>,
}

impl Default for CalcState {
    fn default() -> Self {
        Self::new()
    }
}

impl CalcState {
    pub fn new() -> Self {
        Self {
            mode: Mode::Standard,
            angle: AngleUnit::Deg,
            base: Base::Dec,
            error: None,
            expr: Vec::new(),
            entry: String::new(),
            repeat: None,
            fresh: true,
            evaluated: false,
            history: Vec::new(),
        }
    }

    // ---------- queries ----------

    pub fn entry(&self) -> &str {
        &self.entry
    }

    /// What the small expression line should show: committed tokens plus
    /// the in-progress entry. Empty when nothing has been typed.
    pub fn expression_display(&self) -> String {
        let mut s = String::new();
        for t in &self.expr {
            s.push_str(&self.token_display(*t));
        }
        if !self.expr.is_empty() || self.evaluated {
            // show the raw in-progress operand as typed
            if !self.entry.is_empty() && !self.evaluated {
                s.push_str(&self.entry);
            }
        }
        s
    }

    /// What the big result line shows: live evaluation when an
    /// expression is in progress, otherwise the raw entry (so typed
    /// states like "0." survive), "0" when blank.
    pub fn result_display(&self) -> String {
        if self.error.is_some() {
            return "Error".into();
        }
        if self.evaluated || !self.entry.is_empty() && self.expr.is_empty() {
            return if self.entry.is_empty() {
                "0".into()
            } else {
                self.entry.clone()
            };
        }
        if let Ok(v) = self.preview() {
            return self.fmt_value(v);
        }
        if self.entry.is_empty() {
            "0".into()
        } else {
            self.entry.clone()
        }
    }

    /// Four-base readout for programmer mode: (hex, dec, oct, bin).
    pub fn base_readout(&self) -> Option<(String, String, String, String)> {
        if self.mode != Mode::Programmer {
            return None;
        }
        let v = self.current_value().ok()?.as_i64() as u64;
        Some((
            format!("{v:X}"),
            format!("{}", v as i64),
            format!("{v:o}"),
            format!("{v:b}"),
        ))
    }

    fn token_display(&self, t: Token) -> String {
        match t {
            Token::Val(v) => self.fmt_value(v),
            Token::Op(op) => format!(" {} ", op.symbol()),
            Token::LParen => "(".into(),
            Token::RParen => ") ".into(),
        }
    }

    // ---------- input ----------

    pub fn input_digit(&mut self, d: u8) {
        if self.error.is_some() {
            self.clear_all();
        }
        if !self.base.digit_valid(d) {
            return;
        }
        if self.fresh || self.evaluated {
            self.entry.clear();
            self.fresh = false;
            self.evaluated = false;
            // a digit after ")" or a committed value starts a new
            // operand — commit nothing, just leave expr as is (implicit
            // multiplication is intentionally not supported)
        }
        if self.entry.len() >= MAX_ENTRY_LEN {
            return;
        }
        let c = if d < 10 {
            (b'0' + d) as char
        } else {
            (b'A' + (d - 10)) as char
        };
        // avoid leading zeros stacking in non-hex bases
        if self.entry == "0" && self.base != Base::Hex {
            self.entry.clear();
        }
        self.entry.push(c);
    }

    pub fn input_dot(&mut self) {
        if self.mode == Mode::Programmer || self.error.is_some() {
            return;
        }
        if self.fresh || self.evaluated {
            self.entry = "0".into();
            self.fresh = false;
            self.evaluated = false;
        }
        if !self.entry.contains('.') {
            if self.entry.is_empty() {
                self.entry.push('0');
            }
            self.entry.push('.');
        }
    }

    pub fn toggle_sign(&mut self) {
        if self.error.is_some() {
            return;
        }
        if self.entry.starts_with('-') {
            self.entry.remove(0);
        } else if self.mode == Mode::Programmer {
            // two's-complement negate of the current value
            if let Ok(v) = self.current_value() {
                self.entry = self.fmt_value(Value::I(v.as_i64().wrapping_neg()));
                self.fresh = false;
            }
        } else {
            if self.entry.is_empty() {
                self.entry = "0".into();
                self.fresh = false;
                self.evaluated = false;
            }
            self.entry.insert(0, '-');
        }
    }

    pub fn backspace(&mut self) {
        if self.error.is_some() {
            self.error = None;
            return;
        }
        if self.evaluated {
            return;
        }
        self.entry.pop();
        self.fresh = false;
    }

    pub fn clear_entry(&mut self) {
        self.entry.clear();
        self.error = None;
        self.fresh = true;
        self.evaluated = false;
    }

    pub fn clear_all(&mut self) {
        self.expr.clear();
        self.entry.clear();
        self.error = None;
        self.fresh = true;
        self.evaluated = false;
        self.repeat = None;
    }

    /// `EE` — begin an exponent for scientific-notation input ("5e3").
    pub fn input_exp(&mut self) {
        if self.mode == Mode::Programmer || self.error.is_some() {
            return;
        }
        if self.fresh || self.evaluated {
            self.entry = "1".into();
            self.fresh = false;
            self.evaluated = false;
        }
        // only after digits/sign, and only one exponent marker
        if self.entry.is_empty() || self.entry.ends_with(['e', 'E']) {
            return;
        }
        if !self.entry.contains(['e', 'E']) && self.entry.chars().any(|c| c.is_ascii_digit()) {
            self.entry.push('e');
        }
    }

    /// `Ans` — recall the most recent result into the entry.
    pub fn input_ans(&mut self) {
        if self.error.is_some() {
            return;
        }
        if let Some(h) = self.history.first() {
            self.entry = h.result.clone();
            self.fresh = true;
            self.evaluated = false;
        }
    }

    pub fn input_const(&mut self, c: Const) {
        if self.mode == Mode::Programmer || self.error.is_some() {
            return;
        }
        let v = match c {
            Const::Pi => std::f64::consts::PI,
            Const::E => std::f64::consts::E,
        };
        self.entry = fmt_f64(v);
        self.fresh = false;
        self.evaluated = false;
    }

    pub fn input_binary(&mut self, op: BinOp) {
        if self.error.is_some() || !op.allowed_in(self.mode) {
            return;
        }
        // "-" while typing a negative operand: wait for digits
        if self.entry == "-" {
            return;
        }
        if self.entry.is_empty() {
            match self.expr.last() {
                // unary minus: "2 × − 3" — start a negative operand
                Some(Token::Op(_) | Token::LParen) if op == BinOp::Sub => {
                    self.entry = "-".into();
                    self.fresh = false;
                    self.evaluated = false;
                    return;
                }
                // "(" followed by a non-minus operator is invalid
                Some(Token::LParen) => return,
                // op correction: "2 + ×" -> "2 ×"
                Some(Token::Op(_)) => {
                    *self.expr.last_mut().unwrap() = Token::Op(op);
                    return;
                }
                // nothing at all: "×" starts "0 ×"; leading "−" signs
                None if op == BinOp::Sub => {
                    self.entry = "-".into();
                    self.fresh = false;
                    self.evaluated = false;
                    return;
                }
                None => self.expr.push(Token::Val(self.zero())),
                // value or ")" committed already — fine
                _ => {}
            }
        } else {
            match self.parse_entry() {
                Ok(v) => self.expr.push(Token::Val(v)),
                Err(e) => {
                    self.error = Some(e);
                    return;
                }
            }
        }
        self.entry.clear();
        self.expr.push(Token::Op(op));
        self.fresh = true;
        self.evaluated = false;
    }

    pub fn input_lparen(&mut self) {
        if self.error.is_some() || self.mode == Mode::Standard {
            return;
        }
        // "(" mid-entry would need implicit multiplication — not supported
        if !self.fresh && !self.entry.is_empty() {
            return;
        }
        // "(" only valid after an operator, "(", or at the start
        if matches!(self.expr.last(), Some(Token::Val(_) | Token::RParen)) {
            return;
        }
        self.entry.clear();
        self.expr.push(Token::LParen);
        self.fresh = true;
        self.evaluated = false;
    }

    pub fn input_rparen(&mut self) {
        if self.error.is_some() || self.mode == Mode::Standard {
            return;
        }
        // commit pending entry
        if !self.entry.is_empty() {
            match self.parse_entry() {
                Ok(v) => self.expr.push(Token::Val(v)),
                Err(e) => {
                    self.error = Some(e);
                    return;
                }
            }
            self.entry.clear();
        }
        let opens = self
            .expr
            .iter()
            .filter(|t| matches!(t, Token::LParen))
            .count();
        let closes = self
            .expr
            .iter()
            .filter(|t| matches!(t, Token::RParen))
            .count();
        if opens <= closes {
            return;
        }
        // ")" right after "(" or an operator is invalid
        if matches!(self.expr.last(), Some(Token::LParen | Token::Op(_))) {
            return;
        }
        self.expr.push(Token::RParen);
        self.fresh = true;
    }

    pub fn input_unary(&mut self, op: UnaryOp) {
        if self.error.is_some() || !op.allowed_in(self.mode) {
            return;
        }
        let v = match self.current_value() {
            Ok(v) => v,
            Err(e) => {
                self.error = Some(e);
                return;
            }
        };
        match self.apply_unary(op, v) {
            Ok(r) => {
                self.entry = self.fmt_value(r);
                self.fresh = false;
                self.evaluated = false;
            }
            Err(e) => self.error = Some(e),
        }
    }

    pub fn input_percent(&mut self) {
        if self.error.is_some() {
            return;
        }
        if self.mode == Mode::Programmer {
            self.input_binary(BinOp::Mod);
            return;
        }
        let v = match self.current_value() {
            Ok(v) => v.as_f64(),
            Err(e) => {
                self.error = Some(e);
                return;
            }
        };
        // context: value of the committed expression without a trailing op
        let ctx = self.context_value();
        let pct = match self.expr.last() {
            Some(Token::Op(BinOp::Add)) | Some(Token::Op(BinOp::Sub)) => {
                ctx.map(|c| c * v / 100.0).unwrap_or(v / 100.0)
            }
            _ => v / 100.0,
        };
        self.entry = fmt_f64(pct);
        self.fresh = false;
    }

    /// Evaluate. Returns the history record on success.
    pub fn equals(&mut self) -> Option<(String, String)> {
        if self.error.is_some() {
            return None;
        }
        // repeat-equals: bare "=" re-applies the last binary op
        let toks = self.committed_tokens();
        let mut repeated = false;
        let result = if toks.is_empty() || toks.iter().all(|t| !matches!(t, Token::Op(_))) {
            let cur = match self.current_value() {
                Ok(v) => v,
                Err(e) => {
                    self.error = Some(e);
                    return None;
                }
            };
            let rep = if self.evaluated || toks.is_empty() {
                self.repeat
            } else {
                None
            };
            if let Some((op, rhs)) = rep {
                match self.apply_binary(op, cur, rhs) {
                    Ok(v) => {
                        self.expr = vec![Token::Val(cur), Token::Op(op), Token::Val(rhs)];
                        repeated = true;
                        v
                    }
                    Err(e) => {
                        self.error = Some(e);
                        return None;
                    }
                }
            } else {
                cur
            }
        } else {
            // record repeat info: last binary op and its right operand
            self.repeat = Self::last_binop(&toks);
            match eval_tokens(&toks) {
                Ok(v) => v,
                Err(e) => {
                    self.error = Some(e);
                    return None;
                }
            }
        };

        let expr_str = if repeated {
            self.full_expr_display(&self.expr.clone())
        } else if toks.is_empty() {
            self.entry.clone()
        } else {
            self.full_expr_display(&toks)
        };
        let result_str = self.fmt_value(result);
        self.entry = result_str.clone();
        self.expr.clear();
        self.fresh = true;
        self.evaluated = true;

        let rec = (expr_str, result_str);
        self.history.insert(
            0,
            HistoryEntry {
                expr: rec.0.clone(),
                result: rec.1.clone(),
            },
        );
        self.history.truncate(MAX_HISTORY);
        Some(rec)
    }

    pub fn recall_history(&mut self, idx: usize) {
        let Some(h) = self.history.get(idx) else {
            return;
        };
        self.entry = h.result.clone();
        self.error = None;
        self.fresh = true;
        self.evaluated = false;
    }

    pub fn clear_history(&mut self) {
        self.history.clear();
    }

    // ---------- mode / base / angle ----------

    pub fn set_mode(&mut self, mode: Mode) {
        if self.mode == mode {
            return;
        }
        // convert in-flight value between domains
        let v = self.current_value().unwrap_or(self.zero());
        let converted = match (self.mode == Mode::Programmer, mode == Mode::Programmer) {
            (false, true) => Value::I(if v.as_f64().is_finite() {
                v.as_f64().clamp(-9.0e18, 9.0e18) as i64
            } else {
                0
            }),
            (true, false) => Value::F(v.as_f64()),
            _ => v,
        };
        self.mode = mode;
        if mode != Mode::Programmer {
            self.base = Base::Dec;
        }
        self.expr = self
            .expr
            .iter()
            .map(|t| match t {
                Token::Val(v) => {
                    Token::Val(if mode == Mode::Programmer {
                        Value::I(v.as_i64())
                    } else {
                        Value::F(v.as_f64())
                    })
                }
                other => *other,
            })
            .collect();
        if self.error.is_none() {
            self.entry = self.fmt_value(converted);
            if self.entry == "0" && self.expr.is_empty() {
                self.entry.clear();
            }
            self.fresh = true;
        }
        self.evaluated = false;
    }

    pub fn set_base(&mut self, base: Base) {
        if self.mode != Mode::Programmer || self.base == base {
            return;
        }
        // reinterpret current entry in the new base
        if let Ok(v) = self.current_value() {
            self.base = base;
            if self.error.is_none() {
                self.entry = if v.as_i64() == 0 && self.entry.is_empty() {
                    String::new()
                } else {
                    self.fmt_value(v)
                };
            }
        } else {
            self.base = base;
        }
    }

    pub fn toggle_angle(&mut self) {
        self.angle = match self.angle {
            AngleUnit::Deg => AngleUnit::Rad,
            AngleUnit::Rad => AngleUnit::Deg,
        };
    }

    // ---------- internals ----------

    fn zero(&self) -> Value {
        if self.mode == Mode::Programmer {
            Value::I(0)
        } else {
            Value::F(0.0)
        }
    }

    fn parse_entry(&self) -> Result<Value, CalcError> {
        let s = self.entry.as_str();
        if self.mode == Mode::Programmer {
            if s.is_empty() || s == "-" {
                return Ok(Value::I(0));
            }
            if self.base == Base::Dec {
                // decimal entry is a signed i64 literal
                return s.parse::<i64>()
                    .map(Value::I)
                    .map_err(|_| CalcError::OutOfRange);
            }
            // non-decimal entry is a u64 bit pattern; a leading "-"
            // (from toggle_sign display) means two's-complement negate
            let neg = s.starts_with('-');
            let digits = s.trim_start_matches('-');
            let u = u64::from_str_radix(digits, self.base.radix())
                .map_err(|_| CalcError::OutOfRange)?;
            let mut i = u as i64;
            if neg {
                i = i.wrapping_neg();
            }
            Ok(Value::I(i))
        } else {
            if s.is_empty() || s == "-" {
                return Ok(Value::F(0.0));
            }
            let v: f64 = s.parse().map_err(|_| CalcError::InvalidExpr)?;
            if !v.is_finite() {
                return Err(CalcError::Overflow);
            }
            Ok(Value::F(v))
        }
    }

    /// Current operand value: entry if present, else last expr value,
    /// else 0.
    fn current_value(&self) -> Result<Value, CalcError> {
        if !self.entry.is_empty() {
            return self.parse_entry();
        }
        for t in self.expr.iter().rev() {
            match t {
                Token::Val(v) => return Ok(*v),
                Token::RParen => break,
                _ => {}
            }
        }
        Ok(self.zero())
    }

    /// Value of committed tokens with any trailing operator dropped;
    /// used as the context for %.
    fn context_value(&self) -> Option<f64> {
        let mut toks = self.expr.clone();
        while matches!(toks.last(), Some(Token::Op(_))) {
            toks.pop();
        }
        if toks.is_empty() {
            return None;
        }
        eval_tokens(&toks).ok().map(|v| v.as_f64())
    }

    /// expr + committed entry, trailing ops dropped, parens balanced.
    fn committed_tokens(&self) -> Vec<Token> {
        let mut toks = self.expr.clone();
        if !self.entry.is_empty() && !self.evaluated {
            if let Ok(v) = self.parse_entry() {
                toks.push(Token::Val(v));
            }
        }
        while matches!(toks.last(), Some(Token::Op(_))) {
            toks.pop();
        }
        // auto-close unclosed parens
        let mut depth = 0i32;
        for t in &toks {
            match t {
                Token::LParen => depth += 1,
                Token::RParen => depth -= 1,
                _ => {}
            }
        }
        for _ in 0..depth.max(0) {
            toks.push(Token::RParen);
        }
        toks
    }

    fn preview(&self) -> Result<Value, CalcError> {
        let toks = self.committed_tokens();
        if toks.is_empty() {
            return Err(CalcError::InvalidExpr);
        }
        eval_tokens(&toks)
    }

    /// Last top-level binary op and right operand for repeat-equals.
    fn last_binop(toks: &[Token]) -> Option<(BinOp, Value)> {
        let mut depth = 0i32;
        let mut last: Option<(BinOp, Value)> = None;
        for (i, t) in toks.iter().enumerate() {
            match t {
                Token::LParen => depth += 1,
                Token::RParen => depth -= 1,
                Token::Op(op) if depth == 0 => {
                    if let Some(Token::Val(v)) = toks.get(i + 1) {
                        last = Some((*op, *v));
                    }
                }
                _ => {}
            }
        }
        last
    }

    fn full_expr_display(&self, toks: &[Token]) -> String {
        let mut s = String::new();
        for t in toks {
            s.push_str(&self.token_display(*t));
        }
        s.trim_end().to_string()
    }

    pub fn fmt_value(&self, v: Value) -> String {
        match v {
            Value::F(f) => fmt_f64(f),
            Value::I(i) => self.fmt_int(i),
        }
    }

    fn fmt_int(&self, v: i64) -> String {
        match self.base {
            Base::Dec => format!("{v}"),
            Base::Hex => format!("{:X}", v as u64),
            Base::Oct => format!("{:o}", v as u64),
            Base::Bin => format!("{:b}", v as u64),
        }
    }

    // ---------- arithmetic ----------

    fn apply_unary(&self, op: UnaryOp, v: Value) -> Result<Value, CalcError> {
        if op == UnaryOp::Not {
            return Ok(Value::I(!v.as_i64()));
        }
        let x = v.as_f64();
        let r = match op {
            UnaryOp::Square => x * x,
            UnaryOp::Cube => x * x * x,
            UnaryOp::Sqrt => {
                if x < 0.0 {
                    return Err(CalcError::Domain);
                }
                x.sqrt()
            }
            UnaryOp::Cbrt => x.cbrt(),
            UnaryOp::Recip => {
                if x == 0.0 {
                    return Err(CalcError::DivByZero);
                }
                1.0 / x
            }
            UnaryOp::Fact => return Self::fact(x),
            UnaryOp::Sin => Self::to_rad(self.angle, x).sin(),
            UnaryOp::Cos => Self::to_rad(self.angle, x).cos(),
            UnaryOp::Tan => {
                let r = Self::to_rad(self.angle, x).tan();
                if !r.is_finite() {
                    return Err(CalcError::Domain);
                }
                r
            }
            UnaryOp::Asin => {
                if !(-1.0..=1.0).contains(&x) {
                    return Err(CalcError::Domain);
                }
                Self::unit_from_rad(self.angle, x.asin())
            }
            UnaryOp::Acos => {
                if !(-1.0..=1.0).contains(&x) {
                    return Err(CalcError::Domain);
                }
                Self::unit_from_rad(self.angle, x.acos())
            }
            UnaryOp::Atan => Self::unit_from_rad(self.angle, x.atan()),
            UnaryOp::Ln => {
                if x <= 0.0 {
                    return Err(CalcError::Domain);
                }
                x.ln()
            }
            UnaryOp::Log10 => {
                if x <= 0.0 {
                    return Err(CalcError::Domain);
                }
                x.log10()
            }
            UnaryOp::Exp => x.exp(),
            UnaryOp::Pow10 => 10f64.powf(x),
            UnaryOp::Abs => x.abs(),
            UnaryOp::Not => unreachable!(),
        };
        // trig results snap to zero at calculator epsilon, absorbing
        // input truncation like sin(pi) = -2e-13
        let r = if matches!(
            op,
            UnaryOp::Sin | UnaryOp::Cos | UnaryOp::Tan | UnaryOp::Asin
                | UnaryOp::Acos | UnaryOp::Atan
        ) && r.abs() < 1e-12
        {
            0.0
        } else {
            r
        };
        if r.is_nan() {
            return Err(CalcError::Domain);
        }
        if !r.is_finite() {
            return Err(CalcError::Overflow);
        }
        Ok(Value::F(r))
    }

    fn fact(x: f64) -> Result<Value, CalcError> {
        if x < 0.0 || x.fract() != 0.0 {
            return Err(CalcError::Domain);
        }
        if x > 170.0 {
            return Err(CalcError::Overflow);
        }
        let mut r = 1.0f64;
        for i in 2..=(x as u64) {
            r *= i as f64;
        }
        Ok(Value::F(r))
    }

    fn to_rad(angle: AngleUnit, x: f64) -> f64 {
        match angle {
            AngleUnit::Deg => x.to_radians(),
            AngleUnit::Rad => x,
        }
    }

    fn unit_from_rad(angle: AngleUnit, x: f64) -> f64 {
        match angle {
            AngleUnit::Deg => x.to_degrees(),
            AngleUnit::Rad => x,
        }
    }

    fn apply_binary(&self, op: BinOp, a: Value, b: Value) -> Result<Value, CalcError> {
        use BinOp::*;
        match op {
            And | Or | Xor | Shl | Shr => {
                let (x, y) = (a.as_i64(), b.as_i64());
                let r = match op {
                    And => x & y,
                    Or => x | y,
                    Xor => x ^ y,
                    Shl => x.wrapping_shl(y as u32),
                    Shr => x.wrapping_shr(y as u32),
                    _ => unreachable!(),
                };
                return Ok(Value::I(r));
            }
            _ => {}
        }
        // integer path when both operands are Int (programmer mode)
        if a.is_int() && b.is_int() {
            let (x, y) = (a.as_i64(), b.as_i64());
            let r = match op {
                Add => x.checked_add(y).ok_or(CalcError::Overflow)?,
                Sub => x.checked_sub(y).ok_or(CalcError::Overflow)?,
                Mul => x.checked_mul(y).ok_or(CalcError::Overflow)?,
                Div => {
                    if y == 0 {
                        return Err(CalcError::DivByZero);
                    }
                    x.checked_div(y).ok_or(CalcError::Overflow)?
                }
                Mod => {
                    if y == 0 {
                        return Err(CalcError::DivByZero);
                    }
                    x.checked_rem(y).ok_or(CalcError::Overflow)?
                }
                Pow => {
                    if !(0..=u32::MAX as i64).contains(&y) {
                        return Err(CalcError::Overflow);
                    }
                    x.checked_pow(y as u32).ok_or(CalcError::Overflow)?
                }
                YRoot => {
                    let r = (x as f64).powf(1.0 / y as f64);
                    if !r.is_finite() {
                        return Err(CalcError::Domain);
                    }
                    return Ok(Value::I(r as i64));
                }
                _ => unreachable!(),
            };
            return Ok(Value::I(r));
        }
        // float path
        let (x, y) = (a.as_f64(), b.as_f64());
        let r = match op {
            Add => x + y,
            Sub => x - y,
            Mul => x * y,
            Div => {
                if y == 0.0 {
                    return Err(CalcError::DivByZero);
                }
                x / y
            }
            Mod => {
                if y == 0.0 {
                    return Err(CalcError::DivByZero);
                }
                x - y * (x / y).trunc()
            }
            Pow => x.powf(y),
            YRoot => x.powf(1.0 / y),
            _ => unreachable!(),
        };
        if r.is_nan() {
            return Err(CalcError::Domain);
        }
        if !r.is_finite() {
            return Err(CalcError::Overflow);
        }
        Ok(Value::F(r))
    }
}

/// Evaluate a token slice with precedence climbing. Assumes balanced
/// parens and no trailing operator.
fn eval_tokens(toks: &[Token]) -> Result<Value, CalcError> {
    let state = CalcState::new(); // only used for apply_binary dispatch
    let mut pos = 0;
    let v = parse_expr(toks, &mut pos, 0, &state)?;
    if pos != toks.len() {
        return Err(CalcError::InvalidExpr);
    }
    Ok(v)
}

fn parse_expr(
    toks: &[Token],
    pos: &mut usize,
    min_prec: u8,
    st: &CalcState,
) -> Result<Value, CalcError> {
    let mut lhs = parse_atom(toks, pos, st)?;
    while let Some(Token::Op(op)) = toks.get(*pos) {
        let prec = op.precedence();
        if prec < min_prec {
            break;
        }
        *pos += 1;
        let next_min = if op.right_assoc() { prec } else { prec + 1 };
        let rhs = parse_expr(toks, pos, next_min, st)?;
        lhs = st.apply_binary(*op, lhs, rhs)?;
    }
    Ok(lhs)
}

fn parse_atom(toks: &[Token], pos: &mut usize, st: &CalcState) -> Result<Value, CalcError> {
    match toks.get(*pos) {
        Some(Token::Val(v)) => {
            *pos += 1;
            Ok(*v)
        }
        Some(Token::LParen) => {
            *pos += 1;
            let v = parse_expr(toks, pos, 0, st)?;
            match toks.get(*pos) {
                Some(Token::RParen) => {
                    *pos += 1;
                    Ok(v)
                }
                _ => Err(CalcError::InvalidExpr),
            }
        }
        // unary minus: "- x"
        Some(Token::Op(BinOp::Sub)) => {
            *pos += 1;
            let v = parse_atom(toks, pos, st)?;
            match v {
                Value::F(f) => Ok(Value::F(-f)),
                Value::I(i) => Ok(Value::I(i.wrapping_neg())),
            }
        }
        _ => Err(CalcError::InvalidExpr),
    }
}

/// Format an f64 for display: up to 12 significant digits, trailing
/// zeros trimmed, e-notation outside 1e-10 <= |v| < 1e16.
pub fn fmt_f64(v: f64) -> String {
    if v == 0.0 {
        return "0".into();
    }
    if !v.is_finite() {
        return "Error".into();
    }
    // 12 significant digits
    let s = format!("{v:.11e}");
    let (mant, exp_s) = s.split_once('e').unwrap();
    let exp: i32 = exp_s.parse().unwrap();
    let mant = mant.trim_end_matches('0').trim_end_matches('.');
    if !(-9..16).contains(&exp) {
        return format!("{mant}e{exp}");
    }
    // reconstruct fixed notation: mant is d.ddddddddd
    let neg = mant.starts_with('-');
    let digits: String = mant.chars().filter(|c| c.is_ascii_digit()).collect();
    let digits = digits.as_str();
    let ndig = digits.len() as i32;
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if exp >= 0 {
        let int_len = exp + 1;
        if ndig <= int_len {
            out.push_str(digits);
            for _ in 0..(int_len - ndig) {
                out.push('0');
            }
        } else {
            out.push_str(&digits[..int_len as usize]);
            out.push('.');
            let frac = digits[int_len as usize..].trim_end_matches('0');
            out.push_str(if frac.is_empty() { "0" } else { frac });
            if frac.is_empty() {
                out.pop(); // remove trailing '.'
            }
        }
    } else {
        out.push_str("0.");
        for _ in 0..(-exp - 1) {
            out.push('0');
        }
        out.push_str(digits);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn st() -> CalcState {
        CalcState::new()
    }

    fn seq(s: &mut CalcState, keys: &str) {
        for c in keys.chars() {
            match c {
                '0'..='9' => s.input_digit(c as u8 - b'0'),
                'a'..='f' => s.input_digit(c as u8 - b'a' + 10),
                '.' => s.input_dot(),
                '+' => s.input_binary(BinOp::Add),
                '-' => s.input_binary(BinOp::Sub),
                '*' => s.input_binary(BinOp::Mul),
                '/' => s.input_binary(BinOp::Div),
                '^' => s.input_binary(BinOp::Pow),
                '(' => s.input_lparen(),
                ')' => s.input_rparen(),
                '%' => s.input_percent(),
                '=' => {
                    s.equals();
                }
                'B' => s.backspace(),
                'n' => s.toggle_sign(),
                _ => panic!("bad test key {c}"),
            }
        }
    }

    fn eval(keys: &str) -> String {
        let mut s = st();
        seq(&mut s, keys);
        s.result_display()
    }

    #[test]
    fn basic_arithmetic() {
        assert_eq!(eval("2+3="), "5");
        assert_eq!(eval("7-10="), "-3");
        assert_eq!(eval("6*7="), "42");
        assert_eq!(eval("20/8="), "2.5");
    }

    #[test]
    fn precedence() {
        assert_eq!(eval("2+3*4="), "14");
        assert_eq!(eval("2*3+4="), "10");
        assert_eq!(eval("10-2*3="), "4");
        assert_eq!(eval("2^3^2="), "512"); // right-assoc
    }

    #[test]
    fn float_artifacts_hidden() {
        assert_eq!(eval("0.1+0.2="), "0.3");
        assert_eq!(eval("1.1*3="), "3.3");
        assert_eq!(eval("2.3-2.2="), "0.1");
    }

    #[test]
    fn chained_and_repeat() {
        let mut s = st();
        seq(&mut s, "2+3=");
        assert_eq!(s.result_display(), "5");
        s.equals();
        assert_eq!(s.result_display(), "8");
        s.equals();
        assert_eq!(s.result_display(), "11");
    }

    #[test]
    fn continue_after_equals() {
        let mut s = st();
        seq(&mut s, "2+3=*2=");
        assert_eq!(s.result_display(), "10");
    }

    #[test]
    fn op_correction() {
        let mut s = st();
        seq(&mut s, "2+*3=");
        assert_eq!(s.result_display(), "6");
    }

    #[test]
    fn percent_semantics() {
        assert_eq!(eval("100+10%="), "110");
        assert_eq!(eval("100-10%="), "90");
        assert_eq!(eval("200*10%="), "20");
        assert_eq!(eval("50%="), "0.5");
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("n5+8="), "3"); // -5 + 8
        assert_eq!(eval("2*n3="), "-6"); // 2 * -3
    }

    #[test]
    fn backspace_and_clear() {
        let mut s = st();
        seq(&mut s, "123B");
        assert_eq!(s.result_display(), "12");
        s.clear_entry();
        assert_eq!(s.result_display(), "0");
        seq(&mut s, "5+");
        s.clear_all();
        assert_eq!(s.result_display(), "0");
        assert_eq!(s.expression_display(), "");
    }

    #[test]
    fn div_by_zero() {
        let mut s = st();
        seq(&mut s, "5/0=");
        assert_eq!(s.result_display(), "Error");
        assert_eq!(s.error, Some(CalcError::DivByZero));
        // recover with a digit
        s.input_digit(7);
        assert_eq!(s.error, None);
        assert_eq!(s.result_display(), "7");
    }

    #[test]
    fn scientific_functions() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        seq(&mut s, "9");
        s.input_unary(UnaryOp::Sqrt);
        assert_eq!(s.result_display(), "3");
        seq(&mut s, "B"); // clears "3" -> empty
        s.clear_all();
        seq(&mut s, "2");
        s.input_unary(UnaryOp::Cube);
        assert_eq!(s.result_display(), "8");
        s.clear_all();
        s.input_unary(UnaryOp::Fact); // 0! = 1
        assert_eq!(s.result_display(), "1");
        s.clear_all();
        seq(&mut s, "5");
        s.input_unary(UnaryOp::Fact);
        assert_eq!(s.result_display(), "120");
        s.clear_all();
        seq(&mut s, "10");
        s.input_unary(UnaryOp::Log10);
        assert_eq!(s.result_display(), "1");
        s.clear_all();
        seq(&mut s, "1");
        s.input_unary(UnaryOp::Ln);
        assert_eq!(s.result_display(), "0");
    }

    #[test]
    fn trig_degrees_radians() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        seq(&mut s, "30");
        s.input_unary(UnaryOp::Sin);
        assert_eq!(s.result_display(), "0.5");
        s.toggle_angle(); // Rad
        s.clear_all();
        s.input_const(Const::Pi);
        s.input_unary(UnaryOp::Sin);
        assert_eq!(s.result_display(), "0");
        s.toggle_angle(); // back to Deg
        s.clear_all();
        seq(&mut s, "1");
        s.input_unary(UnaryOp::Asin);
        assert_eq!(s.result_display(), "90");
    }

    #[test]
    fn parens() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        seq(&mut s, "(2+3)*4=");
        assert_eq!(s.result_display(), "20");
        s.clear_all();
        // unclosed paren auto-closes
        seq(&mut s, "(2+3=");
        assert_eq!(s.result_display(), "5");
    }

    #[test]
    fn constants_and_overflow() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        s.input_const(Const::Pi);
        assert_eq!(s.result_display(), "3.14159265359");
        s.clear_all();
        seq(&mut s, "n1");
        s.input_unary(UnaryOp::Sqrt);
        assert_eq!(s.error, Some(CalcError::Domain));
    }

    #[test]
    fn factorial_domain() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        seq(&mut s, "2.5");
        s.input_unary(UnaryOp::Fact);
        assert_eq!(s.error, Some(CalcError::Domain));
        s.clear_all();
        seq(&mut s, "171");
        s.input_unary(UnaryOp::Fact);
        assert_eq!(s.error, Some(CalcError::Overflow));
    }

    #[test]
    fn programmer_bases() {
        let mut s = st();
        s.set_mode(Mode::Programmer);
        s.set_base(Base::Hex);
        seq(&mut s, "ff");
        assert_eq!(s.result_display(), "FF");
        s.set_base(Base::Dec);
        assert_eq!(s.result_display(), "255");
        s.set_base(Base::Bin);
        assert_eq!(s.result_display(), "11111111");
        s.set_base(Base::Oct);
        assert_eq!(s.result_display(), "377");
    }

    #[test]
    fn programmer_bitwise() {
        let mut s = st();
        s.set_mode(Mode::Programmer);
        s.set_base(Base::Hex);
        seq(&mut s, "f0");
        s.input_binary(BinOp::And);
        seq(&mut s, "0f");
        s.equals();
        assert_eq!(s.result_display(), "0");
        s.clear_all();
        seq(&mut s, "f0");
        s.input_binary(BinOp::Or);
        seq(&mut s, "0f");
        s.equals();
        assert_eq!(s.result_display(), "FF");
        s.input_unary(UnaryOp::Not);
        assert_eq!(s.result_display(), "FFFFFFFFFFFFFF00");
        // shifts
        s.clear_all();
        s.set_base(Base::Dec);
        seq(&mut s, "1");
        s.input_binary(BinOp::Shl);
        seq(&mut s, "8");
        s.equals();
        assert_eq!(s.result_display(), "256");
        // modulo
        s.clear_all();
        seq(&mut s, "17");
        s.input_binary(BinOp::Mod);
        seq(&mut s, "5");
        s.equals();
        assert_eq!(s.result_display(), "2");
    }

    #[test]
    fn programmer_int_division() {
        let mut s = st();
        s.set_mode(Mode::Programmer);
        seq(&mut s, "7/2=");
        assert_eq!(s.result_display(), "3");
    }

    #[test]
    fn base_readout() {
        let mut s = st();
        s.set_mode(Mode::Programmer);
        seq(&mut s, "255");
        let (h, d, o, b) = s.base_readout().unwrap();
        assert_eq!(h, "FF");
        assert_eq!(d, "255");
        assert_eq!(o, "377");
        assert_eq!(b, "11111111");
    }

    #[test]
    fn history_records() {
        let mut s = st();
        seq(&mut s, "2+3=");
        seq(&mut s, "10*2=");
        assert_eq!(s.history.len(), 2);
        assert_eq!(s.history[0].expr, "10 × 2");
        assert_eq!(s.history[0].result, "20");
        assert_eq!(s.history[1].expr, "2 + 3");
        // recall
        s.recall_history(1);
        assert_eq!(s.result_display(), "5");
        s.clear_history();
        assert!(s.history.is_empty());
    }

    #[test]
    fn mode_switch_converts() {
        let mut s = st();
        seq(&mut s, "42.9");
        s.set_mode(Mode::Programmer);
        assert_eq!(s.result_display(), "42");
        s.set_mode(Mode::Standard);
        assert_eq!(s.result_display(), "42");
    }

    #[test]
    fn digit_filtered_by_base() {
        let mut s = st();
        s.set_mode(Mode::Programmer);
        s.set_base(Base::Bin);
        s.input_digit(1);
        s.input_digit(5); // ignored
        s.input_digit(0);
        assert_eq!(s.result_display(), "10");
    }

    #[test]
    fn scientific_notation_display() {
        assert_eq!(fmt_f64(1e16), "1e16");
        assert_eq!(fmt_f64(1.5e-11), "1.5e-11");
        assert_eq!(fmt_f64(1e15), "1000000000000000");
        assert_eq!(fmt_f64(0.000000001), "0.000000001");
        assert_eq!(fmt_f64(0.0000000001), "1e-10");
    }

    #[test]
    fn fmt_f64_cases() {
        assert_eq!(fmt_f64(0.0), "0");
        assert_eq!(fmt_f64(-0.0), "0");
        assert_eq!(fmt_f64(0.3), "0.3");
        assert_eq!(fmt_f64(-2.5), "-2.5");
        assert_eq!(fmt_f64(100.0), "100");
        assert_eq!(fmt_f64(1.0 / 3.0), "0.333333333333");
        assert_eq!(fmt_f64(123_456_789.123_456_79), "123456789.123");
        assert_eq!(fmt_f64(-1e-9), "-0.000000001");
        assert_eq!(fmt_f64(-1e-10), "-1e-10");
        assert_eq!(fmt_f64(f64::MAX), "1.79769313486e308");
    }

    #[test]
    fn huge_operands_no_panic() {
        let mut s = st();
        seq(&mut s, "9");
        for _ in 0..30 {
            s.input_digit(9);
        }
        s.input_binary(BinOp::Mul);
        for _ in 0..30 {
            s.input_digit(9);
        }
        s.equals();
        assert!(s.error.is_none() || s.error == Some(CalcError::Overflow));
    }

    #[test]
    fn rapid_state_churn_no_panic() {
        let mut s = st();
        s.set_mode(Mode::Scientific);
        for i in 0..500u32 {
            match i % 11 {
                0 => s.input_binary(BinOp::Add),
                1 => s.input_binary(BinOp::Mul),
                2 => s.input_digit((i % 10) as u8),
                3 => s.input_unary(UnaryOp::Sqrt),
                4 => s.input_lparen(),
                5 => s.input_rparen(),
                6 => s.input_percent(),
                7 => {
                    s.equals();
                }
                8 => s.backspace(),
                9 => s.toggle_sign(),
                _ => s.input_dot(),
            }
        }
        let _ = s.result_display();
    }
}
