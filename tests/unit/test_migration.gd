extends GcTestCase
## Port of tests/migration.rs: keyboard map, command availability, persistence.

const E := preload("res://core/engine.gd")
const C := preload("res://core/commands.gd")
const BinOp := E.BinOp
const Mode := E.Mode
const Base := E.Base

var _temp_roots: Array = []


func _tmp() -> String:
	var d := DirAccess.create_temp("gosh-calc-test")
	_temp_roots.append(d) # keeps the directory alive until the test ends
	return d.get_current_dir()


func _store(root: String) -> GcStore:
	var s := GcStore.new()
	s.directory = root.path_join("settings Δ with spaces")
	return s


func _key(key: String, primary: bool, alt: bool, mode: Mode, base: Base) -> Variant:
	return C.keyboard(key, primary, alt, mode, base)


func test_modified_keyboard_symbols_and_primary_shortcuts() -> void:
	for pair in [
		["+", C.binary(BinOp.ADD)], ["*", C.binary(BinOp.MUL)], ["(", C.lparen()],
		["~", C.unary(GcEngine.UnaryOp.NOT)], ["%", C.percent()],
	]:
		eq(_key(pair[0], false, false, Mode.SCIENTIFIC, Base.DEC), pair[1], pair[0])
	eq(_key("C", true, false, Mode.STANDARD, Base.DEC), C.copy())
	eq(_key("2", true, false, Mode.STANDARD, Base.DEC), C.set_mode(Mode.SCIENTIFIC))
	eq(_key("f", false, false, Mode.STANDARD, Base.DEC), null)
	eq(_key("F", false, false, Mode.PROGRAMMER, Base.HEX), C.digit(15))
	eq(_key("+", false, true, Mode.STANDARD, Base.DEC), null)


func test_invalid_digits_are_disabled_and_not_dispatched() -> void:
	var app := GcAppState.new()
	app.dispatch(C.set_mode(Mode.PROGRAMMER))
	app.dispatch(C.set_base(Base.BIN))
	check(not app.enabled(C.digit(2)))
	check(not app.enabled(C.dot()))
	app.dispatch(C.digit(8))
	eq(app.calc.result_display(), "0")
	check(app.enabled(C.digit(1)))


func test_numeric_history_recall_survives_base_and_mode_changes() -> void:
	var app := GcAppState.new()
	for c in [C.set_mode(Mode.PROGRAMMER), C.set_base(Base.HEX), C.digit(15), C.digit(15),
			C.binary(BinOp.ADD), C.digit(1), C.equals()]:
		app.dispatch(c)
	eq(app.calc.result_display(), "100")
	app.dispatch(C.set_base(Base.DEC))
	app.dispatch(C.recall(0))
	eq(app.calc.result_display(), "256")
	app.dispatch(C.set_mode(Mode.STANDARD))
	app.dispatch(C.ans())
	eq(app.calc.result_display(), "256")


func test_deeply_nested_expression_is_bounded_and_recovers() -> void:
	var app := GcAppState.new()
	app.dispatch(C.set_mode(Mode.SCIENTIFIC))
	for _i in 10000:
		app.dispatch(C.lparen())
	eq(app.calc.error, GcEngine.CalcError.OUT_OF_RANGE)
	app.dispatch(C.digit(7))
	eq(app.calc.result_display(), "7")


func test_only_durable_changes_request_saving() -> void:
	var app := GcAppState.new()
	check(not app.dispatch(C.digit(1))["persist"])
	check(not app.dispatch(C.copy())["persist"])
	check(not app.dispatch(C.toggle_history())["persist"])
	check(app.dispatch(C.set_theme(GcAppState.ThemePref.DARK))["persist"])
	check(not app.dispatch(C.set_theme(GcAppState.ThemePref.DARK))["persist"])
	check(app.dispatch(C.toggle_angle())["persist"])


func test_legacy_ron_is_imported_with_backup_and_never_changed() -> void:
	var root := _tmp()
	var store := _store(root)
	var legacy := root.path_join("cosmic/dev.goshapps.calc/v1")
	DirAccess.make_dir_recursive_absolute(legacy)
	var history := "[(expr: \"12 + 3 × 4\", result: \"24\")]\r\n"
	_write(legacy.path_join("mode"), "\"scientific\"\r\n")
	_write(legacy.path_join("angle"), "\"rad\"")
	_write(legacy.path_join("history"), history)
	store.legacy = legacy
	var loaded := store.load_state()
	eq(loaded["error"], "")
	eq(loaded["state"]["mode"], Mode.SCIENTIFIC)
	eq(loaded["state"]["angle"], GcEngine.AngleUnit.RAD)
	eq(loaded["state"]["history"][0]["result"], "24")
	check(loaded["notice"] != null)
	eq(_read(legacy.path_join("history")), history)
	eq(_read(store.directory.path_join("legacy-cosmic-v1-backup/history")), history)
	check(FileAccess.file_exists(store.settings_path()))
	eq(store.load_state()["notice"], null)


func test_settings_round_trip_on_unicode_path_and_atomic_replace() -> void:
	var root := _tmp()
	var store := _store(root)
	var state := GcStore.default_saved()
	state["theme"] = GcAppState.ThemePref.DARK
	state["window"] = {"width": 800.0, "height": 900.0, "maximized": true}
	eq(store.save(state), "")
	eq(store.save(state), "")
	var loaded := store.load_state()
	eq(loaded["state"]["theme"], GcAppState.ThemePref.DARK)
	eq(loaded["state"]["window"]["width"], 800.0)
	eq(DirAccess.get_files_at(store.directory).size(), 1) # no temporary files left


func test_corrupt_settings_are_preserved_and_future_schema_is_not_overwritten() -> void:
	var root := _tmp()
	var store := _store(root)
	DirAccess.make_dir_recursive_absolute(store.directory)
	_write(store.settings_path(), "{broken")
	check(store.load_state()["notice"] != null)
	var backups := []
	for f in DirAccess.get_files_at(store.directory):
		if f.contains("corrupt"):
			backups.append(f)
	eq(backups.size(), 1)
	eq(_read(store.directory.path_join(backups[0])), "{broken")
	_write(store.settings_path(), "{\"schema_version\":999}")
	check(not store.load_state()["error"].is_empty())
	eq(_read(store.settings_path()), "{\"schema_version\":999}")


func test_oversized_settings_and_malformed_legacy_are_not_destroyed() -> void:
	var root := _tmp()
	var store := _store(root)
	DirAccess.make_dir_recursive_absolute(store.directory)
	_write(store.settings_path(), " ".repeat(1024 * 1024 + 1))
	check(not store.load_state()["error"].is_empty())
	eq(FileAccess.get_file_as_bytes(store.settings_path()).size(), 1024 * 1024 + 1)
	DirAccess.remove_absolute(store.settings_path())
	var legacy := root.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(legacy)
	_write(legacy.path_join("history"), "not valid RON")
	store.legacy = legacy
	check(not store.load_state()["error"].is_empty())
	check(not FileAccess.file_exists(store.settings_path()))
	check(FileAccess.file_exists(legacy.path_join("history")))


func test_writer_flushes_final_update_at_shutdown() -> void:
	var root := _tmp()
	var store := _store(root)
	var writer := GcWriter.new(store)
	for theme in [GcAppState.ThemePref.LIGHT, GcAppState.ThemePref.DARK, GcAppState.ThemePref.SYSTEM,
			GcAppState.ThemePref.DARK]:
		var s := GcStore.default_saved()
		s["theme"] = theme
		eq(writer.save(s), "")
	writer.close()
	eq(store.load_state()["state"]["theme"], GcAppState.ThemePref.DARK)


func test_window_dimensions_are_bounded() -> void:
	var w := GcAppState.bounded_window({"width": NAN, "height": -1.0, "maximized": false})
	eq(w["width"], 460.0)
	eq(w["height"], 480.0)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_command_line_options() -> void:
	eq(GcApp.cli(PackedStringArray())["handled"], false)
	eq(GcApp.cli(PackedStringArray(["some/file.png"]))["handled"], false)
	var v := GcApp.cli(PackedStringArray(["--version"]))
	check(v["handled"] and v["output"].begins_with("Gosh Calc ") and v["exit_code"] == 0)
	check(GcApp.cli(PackedStringArray(["-V"]))["output"] == v["output"])
	var h := GcApp.cli(PackedStringArray(["--help"]))
	check(h["output"].contains("Usage") and h["exit_code"] == 0)
	var bad := GcApp.cli(PackedStringArray(["--bogus"]))
	check(bad["exit_code"] == 1 and bad["output"].contains("--bogus"))
