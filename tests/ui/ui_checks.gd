extends SceneTree
## End-to-end checks of the real application scene. Every interaction goes
## through Godot's input pipeline: real mouse clicks at button centres and real
## key events, so hit-testing, focus, shortcuts and layout are exercised.
##
## Needs a display (xvfb-run is fine):
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/ui/ui_checks.gd
## GOSH_CALC_SCALE=2 repeats everything at 200% UI scale.

const E := preload("res://core/engine.gd")
const C := preload("res://core/commands.gd")

var main: Control
var passed: Array = []
var failed: Array = []
var _config: DirAccess


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, name: String) -> void:
	if condition:
		passed.append(name)
	else:
		failed.append(name)
		print("FAIL: ", name)


func eq(actual: Variant, expected: Variant, name: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		passed.append(name)
	else:
		failed.append(name)
		print("FAIL: %s (expected %s, got %s)" % [name, var_to_str(expected), var_to_str(actual)])


# ---------- harness ----------

func boot(config_dir: String) -> void:
	OS.set_environment("GOSH_CALC_CONFIG_DIR", config_dir)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()


func shutdown() -> void:
	main.quit_app_for_test()
	root.remove_child(main)
	main.queue_free()
	await process_frame


func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame


func result() -> String:
	return main._display._result.text


func find(node_name: String, from: Node = null) -> Control:
	var start: Node = from if from != null else main
	if start.name == node_name and start is Control:
		return start
	for child in start.get_children():
		var hit := find(node_name, child)
		if hit != null:
			return hit
	return null


func find_key(name: String) -> GcButton:
	return find(name) as GcButton


## A real left click at the centre of a control (window pixel coordinates).
func click(control: Control) -> void:
	assert(control != null)
	var scale: float = main.ui_scale
	var pos := control.get_global_rect().get_center() * scale
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	var down := InputEventMouseButton.new()
	down.position = pos
	down.global_position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := down.duplicate()
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await settle()


func press(name: String) -> void:
	var button := find(name)
	if button == null:
		check(false, "control exists: " + name)
		return
	await click(button)


func key(keycode: int, unicode: int = 0, ctrl: bool = false, shift: bool = false, alt: bool = false) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode as Key
	down.physical_keycode = keycode as Key
	down.unicode = unicode
	down.ctrl_pressed = ctrl
	down.shift_pressed = shift
	down.alt_pressed = alt
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await settle()


const SHIFTED := "+*()%^!&|<>~"


func _keycode_of(ch: String) -> int:
	var c := ch.unicode_at(0)
	if c >= 48 and c <= 57:
		return KEY_0 + c - 48
	if ch.to_upper() != ch.to_lower():
		return KEY_A + ch.to_upper().unicode_at(0) - 65
	match ch:
		"+", "=": return KEY_EQUAL
		"-": return KEY_MINUS
		"*": return KEY_8
		"/": return KEY_SLASH
		".": return KEY_PERIOD
		",": return KEY_COMMA
		"%": return KEY_5
		"^": return KEY_6
		"(": return KEY_9
		")": return KEY_0
		"!": return KEY_1
		"&": return KEY_7
		"|": return KEY_BACKSLASH
		"<": return KEY_COMMA
		">": return KEY_PERIOD
		"~": return KEY_QUOTELEFT
	return KEY_NONE


## Types text on the (virtual) keyboard.
func type(text: String) -> void:
	for ch in text:
		var shift: bool = SHIFTED.contains(ch) or (ch.to_upper() == ch and ch.to_lower() != ch)
		await key(_keycode_of(ch), ch.unicode_at(0), false, shift)


## A dialog measures its wrapped content over a couple of frames while hidden.
func settle_dialog() -> void:
	await settle(8)


func clear() -> void:
	await press("Clear calculation")


# ---------- scenarios ----------

func _run() -> void:
	_config = DirAccess.create_temp("gosh-calc-ui")
	var dir := _config.get_current_dir()
	await boot(dir)
	_check_start_state()
	await _standard()
	await _scientific()
	await _programmer()
	await _dialogs_and_settings()
	await _keyboard_shell()
	await _layout()
	await shutdown()
	await _persistence(dir)
	print("%d checks passed, %d failed (scale %s)" % [passed.size(), failed.size(), OS.get_environment("GOSH_CALC_SCALE")])
	quit(1 if not failed.is_empty() else 0)


func _check_start_state() -> void:
	eq(main.app.calc.mode, E.Mode.STANDARD, "starts in standard mode")
	eq(result(), "0", "starts at zero")
	check(not main._history.visible and not main._dialog.visible, "history and dialogs start closed")
	check(not main._notice_panel.visible, "no notice on a clean start")


func _standard() -> void:
	await press("Standard")
	await clear()
	await type("12+3*4=")
	eq(result(), "24", "shifted keyboard arithmetic and precedence")
	await press("CopyResult")
	check(main._notice_panel.visible and main._notice_label.text == "Copied", "copy result callback shows a confirmation")
	await press("DismissNotice") # the toast covers the bottom key row until dismissed
	check(not main._notice_panel.visible, "notice can be dismissed")
	await clear()
	await type("2+3==")
	eq(result(), "8", "repeat equals")
	await clear()
	await type("100+10%=")
	eq(result(), "110", "contextual percent")
	await clear()
	await type("1/0=")
	eq(result(), "Error", "division by zero")
	check(main._display._error.visible and main._display._error.text == "Division by zero", "error detail is shown")
	await type("7")
	eq(result(), "7", "error recovery")
	await press("Square")
	eq(result(), "49", "square button")
	await press("Square root")
	eq(result(), "7", "square root button")
	await press("Toggle sign")
	eq(result(), "-7", "sign toggle")
	await clear()
	await type("123")
	await press("Backspace")
	eq(result(), "12", "backspace")
	await press("Clear entry")
	eq(result(), "0", "clear entry")
	await clear()
	for digit in "0123456789":
		await press(digit)
	eq(result(), "123456789", "all decimal digit callbacks")
	for case in [["Add", "1", "9"], ["Subtract", "1", "7"], ["Multiply", "2", "16"], ["Divide", "2", "4"]]:
		await clear()
		await press("8")
		await press(case[0])
		await press(case[1])
		await press("Equals")
		eq(result(), case[2], "%s standard callback" % case[0])
	await clear()
	await press("1")
	await press("Decimal point")
	await press("5")
	eq(result(), "1.5", "decimal point callback")
	# clicking keys must not leave keyboard focus on them (Enter stays "equals")
	await clear()
	await press("3")
	await press("Add")
	await press("4")
	await key(KEY_ENTER)
	eq(result(), "7", "Enter after a mouse click evaluates instead of re-pressing the key")


func _scientific() -> void:
	await press("Scientific")
	await clear()
	await type("(2+3)*4=")
	eq(result(), "20", "scientific parentheses")
	await clear()
	await type("30")
	if main._display._angle.text != "DEG":
		await press("AngleUnit")
	await press("Sine")
	eq(result(), "0.5", "degree trigonometry")
	await press("Inverse sine")
	eq(result(), "30", "inverse trigonometry")
	await clear()
	await type("5")
	await press("Scientific notation")
	await type("3=")
	eq(result(), "5000", "EE entry")
	await clear()
	await press("Last answer")
	eq(result(), "5000", "Ans recall")
	await clear()
	await press("Pi")
	check(result().begins_with("3.14159"), "pi constant")
	await clear()
	await type("3")
	await press("Factorial")
	eq(result(), "6", "factorial")
	var unary_cases := [
		["Square", "2", 4.0], ["Cube", "2", 8.0], ["Square root", "9", 3.0],
		["Cube root", "27", 3.0], ["Reciprocal", "4", 0.25], ["Factorial", "5", 120.0],
		["Sine", "30", 0.5], ["Cosine", "60", 0.5], ["Tangent", "45", 1.0],
		["Natural logarithm", "1", 0.0], ["Inverse sine", "0.5", 30.0],
		["Inverse cosine", "0.5", 60.0], ["Inverse tangent", "1", 45.0],
		["Logarithm", "100", 2.0], ["Exponential", "1", exp(1.0)],
		["Power of ten", "2", 100.0], ["Absolute value", "2", 2.0],
	]
	for case in unary_cases:
		await clear()
		await type(case[1])
		if case[0] == "Absolute value":
			await press("Toggle sign")
		await press(case[0])
		check(absf(float(result()) - case[2]) < 1e-9, "%s numeric callback" % case[0])
	for case in [["Power", "2", "3", "8"], ["Nth root", "27", "3", "3"]]:
		await clear()
		await type(case[1])
		await press(case[0])
		await type(case[2])
		await press("Equals")
		eq(result(), case[3], "%s numeric callback" % case[0])
	await clear()
	await press("Euler's number")
	check(absf(float(result()) - exp(1.0)) < 1e-9, "Euler constant callback")
	await press("Toggle angle unit")
	eq(main._display._angle.text, "RAD", "RAD selector")
	await clear()
	await press("Pi")
	await press("Sine")
	check(absf(float(result())) < 1e-9, "radian trigonometry")
	await press("Toggle angle unit")
	# traverse every scientific control
	var traversed := 0
	for grid in main._keypad._grids:
		for button in grid.get_children():
			await clear()
			await type("2")
			if not button.disabled:
				await click(button)
			traversed += 1
	check(traversed == 47, "scientific control traversal (%d)" % traversed)


func _programmer() -> void:
	await press("Programmer")
	await clear()
	await press("BaseHEX")
	await type("FF+1=")
	eq(result(), "100", "programmer HEX arithmetic")
	await press("BaseDEC")
	eq(result(), "256", "base conversion")
	await press("HistoryToggle")
	await press("Entry0")
	eq(result(), "256", "numeric history recall across bases")
	await press("CloseHistory")
	await press("BaseBIN")
	check(find_key("2").disabled, "invalid binary digit disabled")
	await press("BaseOCT")
	check(find_key("8").disabled, "invalid octal digit disabled")
	await press("BaseDEC")
	await clear()
	await type("5&3=")
	eq(result(), "1", "bitwise AND from the keyboard")
	for case in [["Shift left", "2", "3", "16"], ["Shift right", "16", "2", "4"], ["Bitwise AND", "5", "3", "1"],
			["Bitwise OR", "5", "2", "7"], ["Bitwise XOR", "5", "3", "6"], ["Modulo", "17", "5", "2"]]:
		await clear()
		await type(case[1])
		await press(case[0])
		await type(case[2])
		await press("Equals")
		eq(result(), case[3], "%s numeric callback" % case[0])
	await clear()
	await type("5")
	await press("Bitwise NOT")
	eq(result(), "-6", "bitwise NOT callback")
	await clear()
	await press("BaseHEX")
	for digit in "ABCDEF":
		await press(digit)
	eq(result(), "ABCDEF", "all hexadecimal digit callbacks")
	await press("BaseDEC")
	await clear()
	await type("9007199254740993+1=")
	eq(result(), "9007199254740994", "integer arithmetic beyond f64 precision")
	check(main._display._readout.visible, "base readout is visible in programmer mode")
	eq(main._display._base_buttons[E.Base.HEX][1].text, "20000000000002", "base readout shows the exact value in hex")


func _dialogs_and_settings() -> void:
	await press("Standard")
	await press("SettingsButton")
	await settle_dialog()
	check(main._dialog.visible and main.app.dialog == GcAppState.Dialog.SETTINGS, "settings dialog opens")
	for theme in ["light", "dark", "system"]:
		await press("Theme" + theme.capitalize())
		await settle_dialog()
		eq(GcAppState.theme_css(main.app.theme), theme, "%s theme updates immediately" % theme)
	await press("CloseDialog")
	check(not main._dialog.visible, "dialog closes")
	await press("ShortcutsButton")
	await settle_dialog()
	check(main._dialog.visible, "shortcut dialog opens")
	var found_enter := false
	for label in main._dialog.find_children("*", "Label", true, false):
		if (label as Label).text.contains("Enter"):
			found_enter = true
	check(found_enter, "shortcut dialog lists Enter")
	await press("DialogDone")
	check(not main._dialog.visible, "Done closes the dialog")
	# history: clearing empties it and disables the button
	await press("HistoryToggle")
	await press("ClearHistory")
	check(find("ClearHistory").disabled, "empty history clear is disabled")
	await press("CloseHistory")
	# every key is labelled and big enough, and nothing overflows horizontally
	var window_w := float(main.size.x)
	var keys := []
	for grid in main._keypad._grids:
		keys.append_array(grid.get_children())
	check(keys.size() > 0, "keypad has keys")
	var labelled := true
	var tall := true
	var inside := true
	for button in keys:
		labelled = labelled and not (button as GcButton).accessibility_name.is_empty() and not (button as GcButton).tooltip_text.is_empty()
		tall = tall and button.size.y >= 40.0
		var r: Rect2 = button.get_global_rect()
		inside = inside and r.position.x >= 0.0 and r.end.x <= window_w + 0.5
	check(labelled, "accessible keypad labels and tooltips")
	check(tall, "readable keypad height")
	check(inside, "no horizontal page overflow")
	# history clear after real calculations
	await clear()
	await type("2+2=")
	await press("HistoryToggle")
	check(not find("ClearHistory").disabled, "history clear enabled with entries")
	await press("ClearHistory")
	check(find("ClearHistory").disabled, "history clear empties the list")
	await press("CloseHistory")


func _keyboard_shell() -> void:
	await clear()
	# keyboard shortcuts through real key events
	await key(KEY_2, 0, true)
	eq(main.app.calc.mode, E.Mode.SCIENTIFIC, "Ctrl+2 switches to scientific")
	await key(KEY_3, 0, true)
	eq(main.app.calc.mode, E.Mode.PROGRAMMER, "Ctrl+3 switches to programmer")
	await key(KEY_1, 0, true)
	eq(main.app.calc.mode, E.Mode.STANDARD, "Ctrl+1 switches to standard")
	await key(KEY_H, "h".unicode_at(0))
	check(main.app.history_open, "h opens history")
	await key(KEY_H, "h".unicode_at(0))
	check(not main.app.history_open, "h closes history")
	await key(KEY_H, 0, true)
	check(main.app.history_open, "Ctrl+H toggles history")
	await key(KEY_H, 0, true)
	await key(KEY_F1)
	eq(main.app.dialog, GcAppState.Dialog.SHORTCUTS, "F1 opens the shortcut guide")
	await type("7")
	eq(result(), "0", "keys are ignored while a dialog is open")
	await key(KEY_ESCAPE)
	eq(main.app.dialog, GcAppState.Dialog.NONE, "Escape closes the dialog")
	await key(KEY_COMMA, 0, true)
	eq(main.app.dialog, GcAppState.Dialog.SETTINGS, "Ctrl+, opens settings")
	# focus trap: Tab never leaves the dialog
	var buttons: Array = main._dialog.focusable_buttons()
	check(buttons.size() >= 2, "dialog has focusable controls")
	var trapped := true
	for i in 12:
		await key(KEY_TAB)
		var focused := root.gui_get_focus_owner()
		var inside: bool = focused != null and main._dialog.is_ancestor_of(focused)
		if not inside:
			print("  focus escaped on Tab %d to %s" % [i + 1, "null" if focused == null else focused.get_path()])
		trapped = trapped and inside
	check(trapped, "Tab focus stays inside the open dialog")
	await key(KEY_ESCAPE)
	# Ctrl+Insert and Ctrl+C copy
	await type("42")
	main.app.notice = null
	main.refresh()
	await key(KEY_INSERT, 0, true)
	check(main.app.notice == "Copied", "Ctrl+Insert copies the result")
	check(DisplayServer.clipboard_get() == "42", "clipboard holds the displayed result")
	await key(KEY_ESCAPE)
	eq(result(), "0", "Escape clears all")
	await type("55")
	await key(KEY_DELETE)
	eq(result(), "0", "Delete clears the entry")
	await type("12")
	await key(KEY_BACKSPACE)
	eq(result(), "1", "Backspace deletes a digit")
	await key(KEY_ESCAPE)
	await type("2^3=")
	eq(result(), "8", "^ is power outside programmer mode")


func _layout() -> void:
	await press("Scientific")
	await press("Standard")
	# window-size dependent layout: sizes are physical pixels
	var scale: float = main.ui_scale
	var cases := [
		["narrow 360x480", Vector2i(360, 480)],
		["compact 420x700", Vector2i(420, 700)],
		["default 460x700", Vector2i(460, 700)],
		["wide 900x700", Vector2i(900, 700)],
	]
	for case in cases:
		root.size = Vector2i(roundi(case[1].x * scale), roundi(case[1].y * scale))
		await settle(4)
		var fits := true
		for node in [main._display, main._keypad, main._calc_scroll]:
			var r: Rect2 = (node as Control).get_global_rect()
			fits = fits and r.end.x <= case[1].x + 0.5 and r.position.x >= -0.5
		check(fits, "%s: calculator stays inside the window" % case[0])
	# scientific layout: two columns when wide, stacked when narrow
	await press("Scientific")
	root.size = Vector2i(roundi(900 * scale), roundi(700 * scale))
	await settle(4)
	var grids: Array = main._keypad._grids
	check(grids[1].get_global_rect().position.x > grids[0].get_global_rect().end.x - 1.0, "scientific keypad is two columns when wide")
	root.size = Vector2i(roundi(500 * scale), roundi(800 * scale))
	await settle(4)
	check(grids[1].get_global_rect().position.y > grids[0].get_global_rect().end.y - 1.0, "scientific keypad stacks in narrow windows")
	# history drawer: side-by-side when wide, overlay when narrow
	await press("Standard")
	root.size = Vector2i(roundi(900 * scale), roundi(700 * scale))
	await settle(4)
	await press("HistoryToggle")
	var cal: Rect2 = main._calc_scroll.get_global_rect()
	var hist: Rect2 = main._history.get_global_rect()
	check(cal.end.x <= hist.position.x + 0.5, "history sits beside the calculator in a wide window")
	root.size = Vector2i(roundi(460 * scale), roundi(700 * scale))
	await settle(4)
	hist = main._history.get_global_rect()
	cal = main._calc_scroll.get_global_rect()
	check(hist.end.x <= main.size.x + 0.5 and hist.size.x <= 300.5 and cal.size.x > hist.size.x, "history overlays the calculator in a narrow window")
	await press("CloseHistory")
	root.size = Vector2i(roundi(460 * scale), roundi(700 * scale))
	await settle(2)


func _persistence(dir: String) -> void:
	# settings were saved by the real app; a fresh start must restore them
	var path := dir.path_join("settings.json")
	check(FileAccess.file_exists(path), "settings file written by the application")
	var store := GcStore.new()
	store.directory = dir
	var saved: Dictionary = store.load_state()["state"]
	var earlier: int = saved["history"].size()
	# second session: change things, quit, relaunch
	await boot(dir)
	eq(main.app.calc.history.size(), earlier, "history restored on the next launch")
	await press("Programmer")
	await clear()
	await type("6*7=")
	await press("SettingsButton")
	await settle_dialog()
	await press("ThemeDark")
	await settle_dialog()
	await press("DialogDone")
	root.size = Vector2i(roundi(520 * main.ui_scale), roundi(640 * main.ui_scale))
	await settle(4)
	await shutdown()
	await boot(dir)
	eq(main.app.calc.mode, E.Mode.PROGRAMMER, "mode restored after relaunch")
	eq(main.app.theme, GcAppState.ThemePref.DARK, "theme restored after relaunch")
	eq(main.app.calc.history.size(), mini(earlier + 1, 100), "history grows across launches")
	eq(main.app.calc.history[0]["result"], "42", "newest history entry restored after relaunch")
	check(absf(float(main.app.window["width"]) - 520.0) < 2.0, "window width restored after relaunch")
	check(absf(float(main.app.window["height"]) - 640.0) < 2.0, "window height restored after relaunch")
	await shutdown()
