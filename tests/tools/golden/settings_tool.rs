use gosh_calc::engine::*;
use gosh_calc::persistence::Store;
use gosh_calc::state::*;
use std::path::PathBuf;

fn entry(expr: &str, result: &str, value: Option<Value>) -> HistoryEntry {
    HistoryEntry { expr: expr.into(), result: result.into(), value }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args[1].as_str() {
        "gen" => {
            let out = PathBuf::from(&args[2]);
            std::fs::create_dir_all(&out).unwrap();
            let fixtures: Vec<(&str, SavedState)> = vec![
                ("default", SavedState::default()),
                ("full", SavedState {
                    mode: Mode::Programmer, angle: AngleUnit::Rad, theme: Theme::Dark,
                    window: WindowState { width: 812.5, height: 931.0, maximized: true },
                    history: vec![
                        entry("12 + 3 × 4", "24", Some(Value::F(24.0))),
                        entry("0xFF + 1", "100", Some(Value::I(256))),
                        entry("big", "9007199254740993", Some(Value::I(9007199254740993))),
                        entry("max", "9223372036854775807", Some(Value::I(i64::MAX))),
                        entry("min", "-9223372036854775808", Some(Value::I(i64::MIN))),
                        entry("1 ÷ 3", "0.333333333333", Some(Value::F(1.0 / 3.0))),
                        entry("tiny", "5e-324", Some(Value::F(5e-324))),
                        entry("huge", "1.79769313486e308", Some(Value::F(f64::MAX))),
                        entry("tab\there \"quoted\" \\ back\nline é π 😀", "x", None),
                        entry("legacy", "42", None),
                        entry("neg", "-2.5", Some(Value::F(-2.5))),
                        entry("1e21", "1e21", Some(Value::F(1e21))),
                        entry("small", "1.5e-7", Some(Value::F(1.5e-7))),
                    ],
                    ..SavedState::default()
                }),
                ("light_scientific", SavedState { mode: Mode::Scientific, theme: Theme::Light, ..SavedState::default() }),
            ];
            for (name, state) in fixtures {
                let dir = out.join(name);
                let store = Store { directory: dir.clone(), legacy: None };
                store.save(&state).unwrap();
            }
        }
        "load" => {
            let store = Store { directory: PathBuf::from(&args[2]), legacy: None };
            match store.load() {
                Ok(l) => println!("{}", serde_json::to_string(&serde_json::json!({"state": l.state, "notice": l.notice})).unwrap()),
                Err(e) => println!("{}", serde_json::json!({"error": e.to_string()})),
            }
        }
        "ser" => {
            for line in std::io::stdin().lines() {
                let bits = u64::from_str_radix(line.unwrap().trim(), 16).unwrap();
                println!("{}", serde_json::to_string(&f64::from_bits(bits)).unwrap());
            }
        }
        _ => panic!(),
    }
}
