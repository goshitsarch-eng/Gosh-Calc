//! Reference oracle: replays command sequences through the real Rust core and
//! prints a snapshot after each step, one JSON line per input line.
use gosh_calc::commands::{keyboard, Command};
use gosh_calc::engine::*;
use gosh_calc::state::*;
use serde_json::{json, Value as J};
use std::io::{BufRead, Write};

fn binop(n: &str) -> BinOp {
    match n {
        "Add" => BinOp::Add, "Sub" => BinOp::Sub, "Mul" => BinOp::Mul, "Div" => BinOp::Div,
        "Mod" => BinOp::Mod, "Pow" => BinOp::Pow, "YRoot" => BinOp::YRoot, "Shl" => BinOp::Shl,
        "Shr" => BinOp::Shr, "And" => BinOp::And, "Or" => BinOp::Or, "Xor" => BinOp::Xor,
        _ => panic!("binop {n}"),
    }
}
fn unop(n: &str) -> UnaryOp {
    match n {
        "Square" => UnaryOp::Square, "Cube" => UnaryOp::Cube, "Sqrt" => UnaryOp::Sqrt,
        "Cbrt" => UnaryOp::Cbrt, "Recip" => UnaryOp::Recip, "Fact" => UnaryOp::Fact,
        "Sin" => UnaryOp::Sin, "Cos" => UnaryOp::Cos, "Tan" => UnaryOp::Tan,
        "Asin" => UnaryOp::Asin, "Acos" => UnaryOp::Acos, "Atan" => UnaryOp::Atan,
        "Ln" => UnaryOp::Ln, "Log10" => UnaryOp::Log10, "Exp" => UnaryOp::Exp,
        "Pow10" => UnaryOp::Pow10, "Not" => UnaryOp::Not, "Abs" => UnaryOp::Abs,
        _ => panic!("unop {n}"),
    }
}
fn mode(n: &str) -> Mode {
    match n { "Standard" => Mode::Standard, "Scientific" => Mode::Scientific, "Programmer" => Mode::Programmer, _ => panic!("mode {n}") }
}
fn base(n: &str) -> Base {
    match n { "Hex" => Base::Hex, "Dec" => Base::Dec, "Oct" => Base::Oct, "Bin" => Base::Bin, _ => panic!("base {n}") }
}
fn theme(n: &str) -> Theme {
    match n { "system" => Theme::System, "light" => Theme::Light, "dark" => Theme::Dark, _ => panic!("theme {n}") }
}
fn dialog(n: &str) -> Dialog {
    match n { "Settings" => Dialog::Settings, "About" => Dialog::About, "Shortcuts" => Dialog::Shortcuts, _ => panic!("dialog {n}") }
}

fn parse(s: &str) -> Command {
    if let Some(n) = s.strip_prefix('D') { if let Ok(d) = n.parse::<u8>() { return Command::Digit(d); } }
    let (head, arg) = match s.split_once(':') { Some((h, a)) => (h, a), None => (s, "") };
    match head {
        "DOT" => Command::Dot,
        "BIN" => Command::Binary(binop(arg)),
        "UN" => Command::Unary(unop(arg)),
        "PCT" => Command::Percent,
        "EQ" => Command::Equals,
        "BS" => Command::Backspace,
        "CE" => Command::ClearEntry,
        "CA" => Command::ClearAll,
        "SIGN" => Command::ToggleSign,
        "BASE" => Command::SetBase(base(arg)),
        "ANGLE" => Command::ToggleAngle,
        "LP" => Command::LParen,
        "RP" => Command::RParen,
        "RECALL" => Command::Recall(arg.parse().unwrap()),
        "CLRH" => Command::ClearHistory,
        "MODE" => Command::SetMode(mode(arg)),
        "ANS" => Command::Ans,
        "EE" => Command::Exp,
        "CONST" => Command::Constant(if arg == "Pi" { Const::Pi } else { Const::E }),
        "COPY" => Command::Copy,
        "THIST" => Command::ToggleHistory,
        "DLG" => Command::ShowDialog(dialog(arg)),
        "CLOSE" => Command::CloseDialog,
        "THEME" => Command::SetTheme(theme(arg)),
        "WIN" => {
            let p: Vec<&str> = arg.split(',').collect();
            Command::SetWindow(WindowState { width: p[0].parse().unwrap(), height: p[1].parse().unwrap(), maximized: p[2] == "1" })
        }
        "DISMISS" => Command::DismissNotice,
        "QUIT" => Command::Quit,
        _ => panic!("command {s}"),
    }
}

fn cmd_name(c: Command) -> String {
    match c {
        Command::Digit(d) => format!("D{d}"),
        Command::Dot => "DOT".into(),
        Command::Binary(o) => format!("BIN:{o:?}"),
        Command::Unary(o) => format!("UN:{o:?}"),
        Command::Percent => "PCT".into(),
        Command::Equals => "EQ".into(),
        Command::Backspace => "BS".into(),
        Command::ClearEntry => "CE".into(),
        Command::ClearAll => "CA".into(),
        Command::ToggleSign => "SIGN".into(),
        Command::SetBase(b) => format!("BASE:{b:?}"),
        Command::ToggleAngle => "ANGLE".into(),
        Command::LParen => "LP".into(),
        Command::RParen => "RP".into(),
        Command::Recall(i) => format!("RECALL:{i}"),
        Command::ClearHistory => "CLRH".into(),
        Command::SetMode(m) => format!("MODE:{m:?}"),
        Command::Ans => "ANS".into(),
        Command::Exp => "EE".into(),
        Command::Constant(k) => format!("CONST:{k:?}"),
        Command::Copy => "COPY".into(),
        Command::ToggleHistory => "THIST".into(),
        Command::ShowDialog(d) => format!("DLG:{d:?}"),
        Command::CloseDialog => "CLOSE".into(),
        Command::SetTheme(t) => format!("THEME:{}", t.css()),
        Command::SetWindow(_) => "WIN".into(),
        Command::DismissNotice => "DISMISS".into(),
        Command::Quit => "QUIT".into(),
    }
}

fn val(v: Value) -> String {
    match v { Value::F(f) => format!("F:{:016x}", f.to_bits()), Value::I(i) => format!("I:{i}") }
}

fn snap(app: &AppState, enabled: bool, persist: bool, copy: &Option<String>, quit: bool) -> J {
    let c = &app.calc;
    json!({
        "result": c.result_display(),
        "expr": c.expression_display(),
        "entry": c.entry(),
        "error": c.error.map(|e| e.to_string()),
        "readout": c.base_readout().map(|(h,d,o,b)| vec![h,d,o,b]),
        "mode": format!("{:?}", c.mode),
        "base": format!("{:?}", c.base),
        "angle": format!("{:?}", c.angle),
        "enabled": enabled, "persist": persist, "copy": copy, "quit": quit,
        "history_open": app.history_open,
        "dialog": app.dialog.map(|d| format!("{d:?}")),
        "theme": app.theme.css(),
        "window": [app.window.width, app.window.height, app.window.maximized],
        "history": c.history.iter().map(|h| json!([h.expr, h.result, h.value.map(val)])).collect::<Vec<_>>(),
    })
}


fn fnv(h: &mut u64, s: &str) {
    for b in s.bytes() { *h ^= b as u64; *h = h.wrapping_mul(0x100000001b3); }
    *h ^= 0xff; *h = h.wrapping_mul(0x100000001b3);
}

fn canon(app: &AppState, enabled: bool, persist: bool, copy: &Option<String>, quit: bool) -> String {
    let c = &app.calc;
    let mut h: u64 = 0xcbf29ce484222325;
    for e in &c.history {
        fnv(&mut h, &e.expr);
        fnv(&mut h, &e.result);
        fnv(&mut h, &e.value.map(val).unwrap_or_else(|| "-".into()));
    }
    let f = |b: bool| if b { "1" } else { "0" };
    let fields: Vec<String> = vec![
        c.result_display(),
        c.expression_display(),
        c.entry().to_string(),
        c.error.map(|e| e.to_string()).unwrap_or_else(|| "-".into()),
        c.base_readout().map(|(a, b, o, d)| format!("{a},{b},{o},{d}")).unwrap_or_else(|| "-".into()),
        format!("{:?}", c.mode), format!("{:?}", c.base), format!("{:?}", c.angle),
        f(enabled).into(), f(persist).into(),
        copy.as_ref().map(|s| format!("={s}")).unwrap_or_else(|| "~".into()),
        f(quit).into(), f(app.history_open).into(),
        app.dialog.map(|d| format!("{d:?}")).unwrap_or_else(|| "-".into()),
        app.theme.css().into(),
        format!("{:016x},{:016x},{}", app.window.width.to_bits(), app.window.height.to_bits(), f(app.window.maximized)),
        c.history.len().to_string(),
        format!("{h:016x}"),
    ];
    fields.join("\t")
}

fn main() {
    let stdin = std::io::stdin();
    let mut out = std::io::BufWriter::new(std::io::stdout().lock());
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let req: J = serde_json::from_str(&line).unwrap();
        let resp = if let Some(bits) = req.get("fmt") {
            let f = f64::from_bits(u64::from_str_radix(bits.as_str().unwrap(), 16).unwrap());
            json!(fmt_f64(f))
        } else if let Some(key) = req.get("key") {
            let m = mode(req["mode"].as_str().unwrap());
            let b = base(req["base"].as_str().unwrap());
            let r = keyboard(key.as_str().unwrap(), req["primary"].as_bool().unwrap(), req["alt"].as_bool().unwrap(), m, b);
            json!(r.map(cmd_name))
        } else {
            // {"seq":[...], "history":[[expr,result,"F:..."|"I:.."|null],...], "mode":..}
            let mut app = AppState::default();
            if let Some(h) = req.get("history") {
                for e in h.as_array().unwrap() {
                    let v = e[2].as_str().map(|s| {
                        let (k, rest) = s.split_at(2);
                        if k == "F:" { Value::F(f64::from_bits(u64::from_str_radix(rest, 16).unwrap())) } else { Value::I(rest.parse().unwrap()) }
                    });
                    app.calc.history.push(HistoryEntry { expr: e[0].as_str().unwrap().into(), result: e[1].as_str().unwrap().into(), value: v });
                }
            }
            let mut steps = vec![];
            for c in req["seq"].as_array().unwrap() {
                let command = parse(c.as_str().unwrap());
                let enabled = app.enabled(command);
                let eff = app.dispatch(command);
                if req.get("verbose").is_some() {
                    steps.push(snap(&app, enabled, eff.persist, &eff.copy, eff.quit));
                } else {
                    steps.push(json!(canon(&app, enabled, eff.persist, &eff.copy, eff.quit)));
                }
            }
            json!(steps)
        };
        writeln!(out, "{}", resp).unwrap();
    }
}
