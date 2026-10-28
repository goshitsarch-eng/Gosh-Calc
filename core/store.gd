class_name GcStore
extends RefCounted
## Bounded, versioned settings with atomic replacement and read-only legacy
## import. The file format and location are unchanged from Gosh Calc 0.2, so an
## existing settings.json keeps working.

const APP_ID := "dev.goshapps.calc"
const MAX_FILE_BYTES := 1024 * 1024

static var _counter := 0

var directory := ""
## Old libcosmic config directory to import from on first run; "" when none.
var legacy := ""


## Returns {"store": GcStore or null, "error": String}.
static func discover() -> Dictionary:
	var base := OS.get_config_dir()
	if base.is_empty():
		return {"store": null, "error": "Cannot find your configuration directory."}
	var store := GcStore.new()
	var override := OS.get_environment("GOSH_CALC_CONFIG_DIR")
	store.directory = override if not override.is_empty() else base.path_join(APP_ID)
	# Only Linux ever had cosmic-config user data. Flatpak's XDG base is already
	# scoped to this app; no host-filesystem permission is needed.
	if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		store.legacy = base.path_join("cosmic").path_join(APP_ID).path_join("v1")
	return {"store": store, "error": ""}


func settings_path() -> String:
	return directory.path_join("settings.json")


static func default_saved() -> Dictionary:
	return {
		"schema_version": GcAppState.SCHEMA_VERSION,
		"mode": GcEngine.Mode.STANDARD,
		"angle": GcEngine.AngleUnit.DEG,
		"history": [],
		"theme": GcAppState.ThemePref.SYSTEM,
		"window": GcAppState.default_window(),
	}


static func _io_error(err: int) -> String:
	return "Cannot read or save calculator settings: %s" % error_string(err)


static func _unique_id() -> String:
	_counter += 1
	return "%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), _counter]


## Returns {"error": String, "state": Dictionary, "notice": null or String}.
## A non-empty error means saving must be disabled (data was preserved).
func load_state() -> Dictionary:
	var path := settings_path()
	if FileAccess.file_exists(path):
		var read := _read_bounded(path)
		if not read["error"].is_empty():
			return _load_failure(read["error"])
		var bytes: PackedByteArray = read["bytes"]
		var text := bytes.get_string_from_utf8()
		var parsed := {"ok": false}
		if text.to_utf8_buffer() == bytes: # reject invalid UTF-8
			parsed = GcJson.parse(text)
		var loaded: Variant = null
		if parsed["ok"]:
			loaded = saved_from_json(parsed["value"])
		if loaded != null:
			if loaded["schema_version"] != GcAppState.SCHEMA_VERSION:
				return _load_failure("Settings were written by a newer version. They have been preserved; saving is disabled.")
			sanitize(loaded)
			return {"error": "", "state": loaded, "notice": null}
		var backup := directory.path_join("settings.corrupt.%s.json" % _unique_id())
		var copy_err := DirAccess.copy_absolute(path, backup)
		if copy_err != OK:
			return _load_failure("Cannot back up unreadable settings: %s. Saving is disabled." % error_string(copy_err))
		return {
			"error": "", "state": default_saved(),
			"notice": "Unreadable settings were backed up. Starting with defaults.",
		}
	var state := default_saved()
	if legacy.is_empty() or not DirAccess.dir_exists_absolute(legacy):
		return {"error": "", "state": state, "notice": null}
	var mode: Variant = _read_legacy("mode", TYPE_STRING)
	if mode is Dictionary:
		return _load_failure(mode["error"])
	if mode != null:
		match mode:
			"scientific":
				state["mode"] = GcEngine.Mode.SCIENTIFIC
			"programmer":
				state["mode"] = GcEngine.Mode.PROGRAMMER
			_:
				state["mode"] = GcEngine.Mode.STANDARD
	var angle: Variant = _read_legacy("angle", TYPE_STRING)
	if angle is Dictionary:
		return _load_failure(angle["error"])
	if angle == "rad":
		state["angle"] = GcEngine.AngleUnit.RAD
	var history: Variant = _read_legacy("history", TYPE_ARRAY)
	if history is Dictionary:
		return _load_failure(history["error"])
	if history != null:
		state["history"] = history
	sanitize(state)
	var backup_dir := directory.path_join("legacy-cosmic-v1-backup")
	var mk := DirAccess.make_dir_recursive_absolute(backup_dir)
	if mk != OK:
		return _load_failure(_io_error(mk))
	for name in ["mode", "angle", "history"]:
		var source := legacy.path_join(name)
		var target := backup_dir.path_join(name)
		if FileAccess.file_exists(source) and not FileAccess.file_exists(target):
			var cp := DirAccess.copy_absolute(source, target)
			if cp != OK:
				return _load_failure(_io_error(cp))
	var save_err := save(state)
	if not save_err.is_empty():
		return _load_failure(save_err)
	return {
		"error": "", "state": state,
		"notice": "Imported your previous mode, angle unit and history. Original settings are unchanged.",
	}


static func _load_failure(message: String) -> Dictionary:
	return {"error": message, "state": default_saved(), "notice": null}


## Writes atomically (temporary file + rename). Returns "" or an error message.
func save(state: Dictionary) -> String:
	var mk := DirAccess.make_dir_recursive_absolute(directory)
	if mk != OK:
		return _io_error(mk)
	var copy := state.duplicate(true)
	sanitize(copy)
	var bytes := GcJson.stringify(saved_to_json(copy)).to_utf8_buffer()
	var temporary := directory.path_join(".settings.%s.tmp" % _unique_id())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _io_error(FileAccess.get_open_error())
	file.store_buffer(bytes)
	file.flush()
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
		DirAccess.remove_absolute(temporary)
		return _io_error(write_err)
	var rename_err := DirAccess.rename_absolute(temporary, settings_path())
	if rename_err != OK:
		DirAccess.remove_absolute(temporary)
		return _io_error(rename_err)
	return ""


static func _read_bounded(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": _io_error(FileAccess.get_open_error()), "bytes": PackedByteArray()}
	var bytes := file.get_buffer(MAX_FILE_BYTES + 1)
	file.close()
	if bytes.size() > MAX_FILE_BYTES:
		return {
			"error": "Settings exceed the 1 MiB limit. They have been preserved; saving is disabled.",
			"bytes": PackedByteArray(),
		}
	return {"error": "", "bytes": bytes}


## Returns null when the legacy file is absent, the parsed value, or
## {"error": String} (a Dictionary) when it exists but cannot be imported.
func _read_legacy(name: String, want: int) -> Variant:
	var path := legacy.path_join(name)
	if not FileAccess.file_exists(path):
		return null
	var failure := {"error": "Cannot import legacy %s. Original data is preserved; saving is disabled." % name}
	var read := _read_bounded(path)
	if not read["error"].is_empty():
		return {"error": read["error"]}
	var bytes: PackedByteArray = read["bytes"]
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return failure
	var parsed := GcRon.parse(text)
	if not parsed["ok"]:
		return failure
	var value: Variant = parsed["value"]
	if want == TYPE_STRING:
		return value if typeof(value) == TYPE_STRING else failure
	if typeof(value) != TYPE_ARRAY:
		return failure
	var entries := []
	for item in value:
		var entry: Variant = _legacy_entry(item)
		if entry == null:
			return failure
		entries.append(entry)
	return entries


static func _legacy_entry(item: Variant) -> Variant:
	if typeof(item) != TYPE_DICTIONARY:
		return null
	if typeof(item.get("expr")) != TYPE_STRING or typeof(item.get("result")) != TYPE_STRING:
		return null
	var value: Variant = null
	if item.has("value"):
		var raw: Variant = item["value"]
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("$variant"):
			return null
		match raw["$variant"]:
			"None":
				value = null
			"Some":
				var inner: Variant = raw["$value"]
				if typeof(inner) != TYPE_DICTIONARY or not inner.has("$variant"):
					return null
				var payload: Variant = inner["$value"]
				if inner["$variant"] == "F" and typeof(payload) in [TYPE_FLOAT, TYPE_INT]:
					value = float(payload)
				elif inner["$variant"] == "I" and typeof(payload) == TYPE_INT:
					value = payload
				else:
					return null
			_:
				return null
	return {"expr": item["expr"], "result": item["result"], "value": value}


## Clamp loaded or about-to-be-saved data to safe bounds.
static func sanitize(state: Dictionary) -> void:
	var calc := GcEngine.new()
	calc.history = state["history"]
	calc.sanitize_persisted()
	var kept := []
	for h in calc.history:
		var v: Variant = h["value"]
		if typeof(v) == TYPE_FLOAT and (is_nan(v) or is_inf(v)):
			continue
		kept.append(h)
	state["history"] = kept
	state["window"] = GcAppState.bounded_window(state["window"])


# ---------- JSON mapping (serde-compatible) ----------

const _MODE_NAMES := ["Standard", "Scientific", "Programmer"]
const _ANGLE_NAMES := ["Deg", "Rad"]
const _THEME_NAMES := ["system", "light", "dark"]


static func saved_to_json(state: Dictionary) -> Dictionary:
	var history := []
	for h in state["history"]:
		var entry := {"expr": h["expr"], "result": h["result"]}
		var v: Variant = h["value"]
		if typeof(v) == TYPE_INT:
			entry["value"] = {"I": v}
		elif typeof(v) == TYPE_FLOAT:
			entry["value"] = {"F": v}
		history.append(entry)
	var w: Dictionary = state["window"]
	return {
		"schema_version": state["schema_version"],
		"mode": _MODE_NAMES[state["mode"]],
		"angle": _ANGLE_NAMES[state["angle"]],
		"history": history,
		"theme": _THEME_NAMES[state["theme"]],
		"window": {"width": w["width"], "height": w["height"], "maximized": w["maximized"]},
	}


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Maps parsed JSON to a state dictionary with the strictness of serde:
## missing fields take defaults, present fields must have the right type.
## Returns null when the document does not fit.
static func saved_from_json(doc: Variant) -> Variant:
	if typeof(doc) != TYPE_DICTIONARY:
		return null
	var state := default_saved()
	if doc.has("schema_version"):
		var sv: Variant = doc["schema_version"]
		if typeof(sv) != TYPE_INT or sv < 0 or sv > 4294967295:
			return null
		state["schema_version"] = sv
	if doc.has("mode"):
		var i: int = _MODE_NAMES.find(doc["mode"]) if typeof(doc["mode"]) == TYPE_STRING else -1
		if i < 0:
			return null
		state["mode"] = i
	if doc.has("angle"):
		var i: int = _ANGLE_NAMES.find(doc["angle"]) if typeof(doc["angle"]) == TYPE_STRING else -1
		if i < 0:
			return null
		state["angle"] = i
	if doc.has("theme"):
		var i: int = _THEME_NAMES.find(doc["theme"]) if typeof(doc["theme"]) == TYPE_STRING else -1
		if i < 0:
			return null
		state["theme"] = i
	if doc.has("history"):
		if typeof(doc["history"]) != TYPE_ARRAY:
			return null
		var history := []
		for item in doc["history"]:
			if typeof(item) != TYPE_DICTIONARY:
				return null
			if typeof(item.get("expr")) != TYPE_STRING or typeof(item.get("result")) != TYPE_STRING:
				return null
			var value: Variant = null
			if item.has("value") and item["value"] != null:
				var tagged: Variant = item["value"]
				if typeof(tagged) != TYPE_DICTIONARY or tagged.size() != 1:
					return null
				if tagged.has("F") and _is_number(tagged["F"]):
					value = float(tagged["F"])
				elif tagged.has("I") and typeof(tagged["I"]) == TYPE_INT:
					value = tagged["I"]
				else:
					return null
			history.append({"expr": item["expr"], "result": item["result"], "value": value})
		state["history"] = history
	if doc.has("window"):
		var w: Variant = doc["window"]
		if typeof(w) != TYPE_DICTIONARY:
			return null
		var window := GcAppState.default_window()
		for key in ["width", "height"]:
			if w.has(key):
				if not _is_number(w[key]):
					return null
				window[key] = float(w[key])
		if w.has("maximized"):
			if typeof(w["maximized"]) != TYPE_BOOL:
				return null
			window["maximized"] = w["maximized"]
		state["window"] = window
	return state
