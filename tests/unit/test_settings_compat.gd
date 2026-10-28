extends GcTestCase
## settings.json files written by the Rust releases must load unchanged, and
## re-saving them must reproduce the same bytes (same format, same location).

const FIXTURES := "res://tests/fixtures/rust-0.2"

var _keep: Array = []


func _temp_store() -> GcStore:
	var d := DirAccess.create_temp("gosh-calc-compat")
	_keep.append(d)
	var s := GcStore.new()
	s.directory = d.get_current_dir()
	return s


func _install(name: String) -> GcStore:
	var s := _temp_store()
	var bytes := FileAccess.get_file_as_bytes(FIXTURES.path_join(name).path_join("settings.json"))
	var f := FileAccess.open(s.settings_path(), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return s


func test_rust_written_files_resave_byte_identical() -> void:
	for name in ["default", "full", "light_scientific"]:
		var original := FileAccess.get_file_as_bytes(FIXTURES.path_join(name).path_join("settings.json"))
		var store := _install(name)
		var loaded := store.load_state()
		eq(loaded["error"], "", name)
		eq(loaded["notice"], null, name)
		var other := _temp_store()
		eq(other.save(loaded["state"]), "", name)
		var rewritten := FileAccess.get_file_as_bytes(other.settings_path())
		check(rewritten == original, "%s re-saved differently:\n%s" % [name, rewritten.get_string_from_utf8()])


func test_full_fixture_values_are_exact() -> void:
	var state: Dictionary = _install("full").load_state()["state"]
	eq(state["mode"], GcEngine.Mode.PROGRAMMER)
	eq(state["angle"], GcEngine.AngleUnit.RAD)
	eq(state["theme"], GcAppState.ThemePref.DARK)
	eq(state["window"], {"width": 812.5, "height": 931.0, "maximized": true})
	var h: Array = state["history"]
	eq(h.size(), 13)
	eq(h[0]["value"], 24.0)
	eq(h[2]["value"], 9007199254740993) # beyond 2^53: must stay an exact int
	eq(h[3]["value"], GcEngine.INT_MAX)
	eq(h[4]["value"], GcEngine.INT_MIN)
	eq(h[5]["value"], 1.0 / 3.0)
	eq(GcNum.bits_of(h[6]["value"]), 1) # 5e-324
	eq(h[7]["value"], GcNum.from_bits(GcNum.MAX_FINITE_BITS))
	eq(h[8]["expr"], "tab\there \"quoted\" \\ back\nline é π 😀")
	eq(h[8]["value"], null)
	eq(h[11]["value"], GcNum.parse_f64("1e21"))


func test_serde_float_formatting() -> void:
	for pair in [
		["1e15", "1000000000000000.0"], ["1e16", "1e+16"], ["1.5e16", "1.5e+16"],
		["1e-5", "0.00001"], ["1.234e-5", "0.00001234"], ["1e-6", "1e-6"], ["1.5e-7", "1.5e-7"],
		["100", "100.0"], ["0.1", "0.1"], ["5e-324", "5e-324"], ["1e22", "1e+22"],
	]:
		eq(GcNum.shortest_f64(GcNum.parse_f64(pair[0])), pair[1], pair[0])


func test_type_mismatches_are_rejected_like_serde() -> void:
	for doc in [
		'{"mode":"Nope"}', '{"mode":5}', '{"angle":null}', '{"theme":"Dark"}', '{"history":{}}',
		'{"history":[{"expr":"a"}]}', '{"history":[{"expr":1,"result":"2"}]}',
		'{"history":[{"expr":"a","result":"b","value":{"X":1}}]}',
		'{"history":[{"expr":"a","result":"b","value":{"I":1.5}}]}',
		'{"history":[{"expr":"a","result":"b","value":{"I":1,"F":2}}]}',
		'{"window":{"width":"wide"}}', '{"window":5}', '{"schema_version":1.0}', '{"schema_version":-1}',
		'[]', '5', '"x"', 'null', '{"mode":"Standard",}', '{broken',
	]:
		var parsed := GcJson.parse(doc)
		check(not parsed["ok"] or GcStore.saved_from_json(parsed["value"]) == null, "accepted: " + doc)
	for doc in [
		'{}', '{"unknown":[1,2,{"x":null}]}', '{"mode":"Programmer"}', '{"history":[]}',
		'{"history":[{"expr":"a","result":"b","value":null,"extra":true}]}',
		'{"window":{"width":500}}', '{"window":{"width":500,"height":600,"maximized":false,"x":1}}',
		'{"history":[{"expr":"a","result":"b","value":{"F":5}}]}',
	]:
		var parsed := GcJson.parse(doc)
		check(parsed["ok"] and GcStore.saved_from_json(parsed["value"]) != null, "rejected: " + doc)


func test_invalid_utf8_settings_are_backed_up_not_lost() -> void:
	var store := _temp_store()
	var bytes := PackedByteArray([0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x7D])
	var f := FileAccess.open(store.settings_path(), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var loaded := store.load_state()
	check(loaded["notice"] != null)
	var backups := 0
	for name in DirAccess.get_files_at(store.directory):
		if name.contains("corrupt"):
			backups += 1
			eq(FileAccess.get_file_as_bytes(store.directory.path_join(name)), bytes)
	eq(backups, 1)


func test_hostile_history_is_clamped_on_load() -> void:
	var store := _temp_store()
	var entries := []
	for i in 150:
		entries.append({"expr": "e".repeat(1000), "result": "9".repeat(1000), "value": null})
	var doc := GcStore.default_saved()
	doc["history"] = entries
	var f := FileAccess.open(store.settings_path(), FileAccess.WRITE)
	f.store_string(GcJson.stringify(GcStore.saved_to_json(doc)))
	f.close()
	var state: Dictionary = store.load_state()["state"]
	eq(state["history"].size(), GcEngine.MAX_HISTORY)
	eq(state["history"][0]["expr"].length(), GcEngine.MAX_PERSIST_STR)
