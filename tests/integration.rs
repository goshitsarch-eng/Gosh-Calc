//! Original calculation workflows now exercise the real shared dispatcher.
use gosh_calc::commands::Command as Msg;
use gosh_calc::engine::{Base, BinOp, CalcState, Mode, UnaryOp};
use gosh_calc::state::AppState;
fn apply(state: &mut CalcState, command: Msg) {
    let mut app = AppState {
        calc: std::mem::take(state),
        ..AppState::default()
    };
    app.dispatch(command);
    *state = app.calc;
}

fn run(state: &mut CalcState, msgs: &[Msg]) {
    for m in msgs {
        apply(state, *m);
    }
}

/// Flow: type a full calculation, evaluate, verify history, recall it.
#[test]
fn flow_calculate_and_recall() {
    let mut s = CalcState::new();
    run(
        &mut s,
        &[
            Msg::Digit(1),
            Msg::Digit(2),
            Msg::Binary(BinOp::Add),
            Msg::Digit(3),
            Msg::Binary(BinOp::Mul),
            Msg::Digit(4),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "24"); // precedence: 12 + 3*4
    assert_eq!(s.history.len(), 1);
    assert_eq!(s.history[0].result, "24");

    // start a new calc, recall the previous result into it
    run(
        &mut s,
        &[
            Msg::Digit(1),
            Msg::Digit(0),
            Msg::Binary(BinOp::Sub),
            Msg::Recall(0),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "-14"); // 10 - 24
    assert_eq!(s.history.len(), 2);
}

/// Flow: scientific calculation with parens and a unary function.
#[test]
fn flow_scientific() {
    let mut s = CalcState::new();
    s.set_mode(Mode::Scientific);
    run(
        &mut s,
        &[
            Msg::LParen,
            Msg::Digit(2),
            Msg::Binary(BinOp::Add),
            Msg::Digit(3),
            Msg::RParen,
            Msg::Binary(BinOp::Mul),
            Msg::Digit(4),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "20");

    // sqrt of result, then squared again
    run(&mut s, &[Msg::Unary(UnaryOp::Sqrt)]);
    run(&mut s, &[Msg::Unary(UnaryOp::Square)]);
    assert_eq!(s.result_display(), "20");
}

/// Flow: programmer hex arithmetic, base readout, switching.
#[test]
fn flow_programmer() {
    let mut s = CalcState::new();
    s.set_mode(Mode::Programmer);
    run(
        &mut s,
        &[
            Msg::SetBase(Base::Hex),
            Msg::Digit(15), // F
            Msg::Digit(15), // F
            Msg::Binary(BinOp::Add),
            Msg::Digit(1),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "100"); // 0xFF + 1 = 0x100
    let (h, d, o, b) = s.base_readout().unwrap();
    assert_eq!(
        (h.as_str(), d.as_str(), o.as_str(), b.as_str()),
        ("100", "256", "400", "100000000")
    );

    run(&mut s, &[Msg::SetBase(Base::Dec)]);
    assert_eq!(s.result_display(), "256");
}

/// Flow: error -> recovery does not wedge the app.
#[test]
fn flow_error_recovery() {
    let mut s = CalcState::new();
    run(
        &mut s,
        &[
            Msg::Digit(5),
            Msg::Binary(BinOp::Div),
            Msg::Digit(0),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "Error");
    // any digit clears into a fresh entry
    run(&mut s, &[Msg::Digit(9), Msg::Equals]);
    assert_eq!(s.result_display(), "9");
}

/// Flow: angle unit affects trig; persists in state.
#[test]
fn flow_angle_toggle() {
    let mut s = CalcState::new();
    s.set_mode(Mode::Scientific);
    run(
        &mut s,
        &[Msg::Digit(9), Msg::Digit(0), Msg::Unary(UnaryOp::Sin)],
    );
    assert_eq!(s.result_display(), "1"); // sin(90deg)
    run(&mut s, &[Msg::ToggleAngle, Msg::ClearAll]);
    run(
        &mut s,
        &[Msg::Digit(9), Msg::Digit(0), Msg::Unary(UnaryOp::Sin)],
    );
    assert_eq!(s.result_display(), "0.893996663601"); // sin(90 rad)
}

/// Flow: clear-history empties the drawer model.
#[test]
fn flow_history_clear() {
    let mut s = CalcState::new();
    run(
        &mut s,
        &[
            Msg::Digit(2),
            Msg::Binary(BinOp::Add),
            Msg::Digit(2),
            Msg::Equals,
        ],
    );
    assert_eq!(s.history.len(), 1);
    run(&mut s, &[Msg::ClearHistory]);
    assert!(s.history.is_empty());
}

/// Flow: EE scientific-notation entry, then Ans recall into a new calc.
#[test]
fn flow_exp_and_ans() {
    let mut s = CalcState::new();
    s.set_mode(Mode::Scientific);
    run(
        &mut s,
        &[Msg::Digit(5), Msg::Exp, Msg::Digit(3), Msg::Equals],
    );
    assert_eq!(s.result_display(), "5000"); // 5e3
    run(
        &mut s,
        &[
            Msg::ClearAll,
            Msg::Ans,
            Msg::Binary(BinOp::Mul),
            Msg::Digit(2),
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "10000"); // Ans * 2
}

/// Flow: percent in context.
#[test]
fn flow_percent() {
    let mut s = CalcState::new();
    run(
        &mut s,
        &[
            Msg::Digit(2),
            Msg::Digit(0),
            Msg::Digit(0),
            Msg::Binary(BinOp::Add),
            Msg::Digit(1),
            Msg::Digit(5),
            Msg::Percent,
            Msg::Equals,
        ],
    );
    assert_eq!(s.result_display(), "230"); // 200 + 15% of 200
}
