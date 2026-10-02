use gosh_calc::{
    commands::{keyboard, Command as C},
    engine::{Base, BinOp, CalcError, Mode},
    persistence::{Store, Writer},
    state::{AppState, SavedState, Theme, WindowState},
};
use std::fs;

fn store(directory: &tempfile::TempDir) -> Store {
    Store {
        directory: directory.path().join("settings Δ with spaces"),
        legacy: None,
    }
}

#[test]
fn modified_keyboard_symbols_and_primary_shortcuts() {
    for (key, command) in [
        ("+", C::Binary(BinOp::Add)),
        ("*", C::Binary(BinOp::Mul)),
        ("(", C::LParen),
        ("~", C::Unary(gosh_calc::engine::UnaryOp::Not)),
        ("%", C::Percent),
    ] {
        assert_eq!(
            keyboard(key, false, false, Mode::Scientific, Base::Dec),
            Some(command)
        );
    }
    assert_eq!(
        keyboard("C", true, false, Mode::Standard, Base::Dec),
        Some(C::Copy)
    );
    assert_eq!(
        keyboard("2", true, false, Mode::Standard, Base::Dec),
        Some(C::SetMode(Mode::Scientific))
    );
    assert_eq!(keyboard("f", false, false, Mode::Standard, Base::Dec), None);
    assert_eq!(
        keyboard("F", false, false, Mode::Programmer, Base::Hex),
        Some(C::Digit(15))
    );
    assert_eq!(keyboard("+", false, true, Mode::Standard, Base::Dec), None);
}
#[test]
fn invalid_digits_are_disabled_and_not_dispatched() {
    let mut app = AppState::default();
    app.dispatch(C::SetMode(Mode::Programmer));
    app.dispatch(C::SetBase(Base::Bin));
    assert!(!app.enabled(C::Digit(2)));
    assert!(!app.enabled(C::Dot));
    app.dispatch(C::Digit(8));
    assert_eq!(app.calc.result_display(), "0");
    assert!(app.enabled(C::Digit(1)));
}
#[test]
fn numeric_history_recall_survives_base_and_mode_changes() {
    let mut app = AppState::default();
    for c in [
        C::SetMode(Mode::Programmer),
        C::SetBase(Base::Hex),
        C::Digit(15),
        C::Digit(15),
        C::Binary(BinOp::Add),
        C::Digit(1),
        C::Equals,
    ] {
        app.dispatch(c);
    }
    assert_eq!(app.calc.result_display(), "100");
    app.dispatch(C::SetBase(Base::Dec));
    app.dispatch(C::Recall(0));
    assert_eq!(app.calc.result_display(), "256");
    app.dispatch(C::SetMode(Mode::Standard));
    app.dispatch(C::Ans);
    assert_eq!(app.calc.result_display(), "256");
}
#[test]
fn deeply_nested_expression_is_bounded_and_recovers() {
    let mut app = AppState::default();
    app.dispatch(C::SetMode(Mode::Scientific));
    for _ in 0..10000 {
        app.dispatch(C::LParen);
    }
    assert_eq!(app.calc.error, Some(CalcError::OutOfRange));
    app.dispatch(C::Digit(7));
    assert_eq!(app.calc.result_display(), "7");
}
#[test]
fn only_durable_changes_request_saving() {
    let mut app = AppState::default();
    assert!(!app.dispatch(C::Digit(1)).persist);
    assert!(!app.dispatch(C::Copy).persist);
    assert!(!app.dispatch(C::ToggleHistory).persist);
    assert!(app.dispatch(C::SetTheme(Theme::Dark)).persist);
    assert!(!app.dispatch(C::SetTheme(Theme::Dark)).persist);
    assert!(app.dispatch(C::ToggleAngle).persist);
}
#[test]
fn legacy_ron_is_imported_with_backup_and_never_changed() {
    let tmp = tempfile::tempdir().unwrap();
    let mut store = store(&tmp);
    let legacy = tmp.path().join("cosmic/dev.goshapps.calc/v1");
    fs::create_dir_all(&legacy).unwrap();
    let history = "[(expr: \"12 + 3 × 4\", result: \"24\")]\r\n";
    fs::write(legacy.join("mode"), "\"scientific\"\r\n").unwrap();
    fs::write(legacy.join("angle"), "\"rad\"").unwrap();
    fs::write(legacy.join("history"), history).unwrap();
    store.legacy = Some(legacy.clone());
    let loaded = store.load().unwrap();
    assert_eq!(loaded.state.mode, Mode::Scientific);
    assert_eq!(loaded.state.angle, gosh_calc::engine::AngleUnit::Rad);
    assert_eq!(loaded.state.history[0].result, "24");
    assert!(loaded.notice.is_some());
    assert_eq!(fs::read_to_string(legacy.join("history")).unwrap(), history);
    assert_eq!(
        fs::read_to_string(store.directory.join("legacy-cosmic-v1-backup/history")).unwrap(),
        history
    );
    assert!(store.path().is_file());
    assert!(store.load().unwrap().notice.is_none());
}
#[test]
fn settings_round_trip_on_unicode_path_and_atomic_replace() {
    let tmp = tempfile::tempdir().unwrap();
    let store = store(&tmp);
    let state = SavedState {
        theme: Theme::Dark,
        window: WindowState {
            width: 800.0,
            height: 900.0,
            maximized: true,
        },
        ..SavedState::default()
    };
    store.save(&state).unwrap();
    store.save(&state).unwrap();
    let loaded = store.load().unwrap();
    assert_eq!(loaded.state.theme, Theme::Dark);
    assert_eq!(loaded.state.window.width, 800.0);
    assert_eq!(fs::read_dir(&store.directory).unwrap().count(), 1);
}
#[test]
fn corrupt_settings_are_preserved_and_future_schema_is_not_overwritten() {
    let tmp = tempfile::tempdir().unwrap();
    let store = store(&tmp);
    fs::create_dir_all(&store.directory).unwrap();
    fs::write(store.path(), b"{broken").unwrap();
    assert!(store.load().unwrap().notice.is_some());
    let backups: Vec<_> = fs::read_dir(&store.directory)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.file_name().unwrap().to_string_lossy().contains("corrupt"))
        .collect();
    assert_eq!(backups.len(), 1);
    assert_eq!(fs::read(&backups[0]).unwrap(), b"{broken");
    fs::write(store.path(), b"{\"schema_version\":999}").unwrap();
    assert!(store.load().is_err());
    assert_eq!(fs::read(store.path()).unwrap(), b"{\"schema_version\":999}");
}
#[test]
fn oversized_settings_and_malformed_legacy_are_not_destroyed() {
    let tmp = tempfile::tempdir().unwrap();
    let mut store = store(&tmp);
    fs::create_dir_all(&store.directory).unwrap();
    fs::write(store.path(), vec![b' '; 1024 * 1024 + 1]).unwrap();
    assert!(store.load().is_err());
    assert_eq!(fs::metadata(store.path()).unwrap().len(), 1024 * 1024 + 1);
    fs::remove_file(store.path()).unwrap();
    let legacy = tmp.path().join("legacy");
    fs::create_dir(&legacy).unwrap();
    fs::write(legacy.join("history"), b"not valid RON").unwrap();
    store.legacy = Some(legacy.clone());
    assert!(store.load().is_err());
    assert!(!store.path().exists());
    assert!(legacy.join("history").exists());
}
#[test]
fn writer_flushes_final_update_at_shutdown() {
    let tmp = tempfile::tempdir().unwrap();
    let store = store(&tmp);
    let writer = Writer::new(store.clone()).unwrap();
    for theme in [Theme::Light, Theme::Dark, Theme::System, Theme::Dark] {
        writer
            .save(SavedState {
                theme,
                ..SavedState::default()
            })
            .unwrap();
    }
    drop(writer);
    assert_eq!(store.load().unwrap().state.theme, Theme::Dark);
}
#[test]
fn window_dimensions_are_bounded() {
    let state = WindowState {
        width: f64::NAN,
        height: -1.0,
        maximized: false,
    }
    .bounded();
    assert_eq!(state.width, 460.0);
    assert_eq!(state.height, 480.0);
}
