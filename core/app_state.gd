class_name GcAppState
extends RefCounted
## Application model: the calculator plus persisted preferences and transient
## presentation state. Calculation state is never duplicated in the UI.

enum ThemePref { SYSTEM, LIGHT, DARK }
enum Dialog { NONE, SETTINGS, ABOUT, SHORTCUTS }

const SCHEMA_VERSION := 1
const DEFAULT_WIDTH := 460.0
const DEFAULT_HEIGHT := 700.0

var calc := GcEngine.new()
var theme: ThemePref = ThemePref.SYSTEM
var window := default_window()
var history_open := false
var dialog: Dialog = Dialog.NONE
var notice: Variant = null # String or null


static func theme_label(t: ThemePref) -> String:
	match t:
		ThemePref.LIGHT:
			return "Light"
		ThemePref.DARK:
			return "Dark"
		_:
			return "Follow System"


static func theme_css(t: ThemePref) -> String:
	match t:
		ThemePref.LIGHT:
			return "light"
		ThemePref.DARK:
			return "dark"
		_:
			return "system"


static func default_window() -> Dictionary:
	return {"width": DEFAULT_WIDTH, "height": DEFAULT_HEIGHT, "maximized": false}


## Clamp window geometry to sane bounds; non-finite values fall back to the defaults.
static func bounded_window(w: Dictionary) -> Dictionary:
	var width: float = w.get("width", DEFAULT_WIDTH)
	var height: float = w.get("height", DEFAULT_HEIGHT)
	return {
		"width": clampf(width, 360.0, 2400.0) if is_finite(width) else DEFAULT_WIDTH,
		"height": clampf(height, 480.0, 1600.0) if is_finite(height) else DEFAULT_HEIGHT,
		"maximized": bool(w.get("maximized", false)),
	}


## Builds state from a saved-settings dictionary (see GcStore).
static func from_saved(saved: Dictionary) -> GcAppState:
	var s := GcAppState.new()
	s.calc.set_mode(saved["mode"])
	s.calc.angle = saved["angle"]
	s.calc.history = saved["history"]
	s.calc.sanitize_persisted()
	s.theme = saved["theme"]
	s.window = bounded_window(saved["window"])
	return s


func saved() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"mode": calc.mode,
		"angle": calc.angle,
		"history": calc.history.duplicate(true),
		"theme": theme,
		"window": bounded_window(window),
	}


func enabled(command: Dictionary) -> bool:
	var K := GcCommands.Kind
	match command["k"]:
		K.DIGIT:
			var d: int = command["a"]
			if calc.mode == GcEngine.Mode.PROGRAMMER:
				return GcEngine.digit_valid(calc.base, d)
			return d < 10
		K.DOT:
			return calc.mode != GcEngine.Mode.PROGRAMMER
		K.BINARY:
			return GcEngine.binop_allowed_in(command["a"], calc.mode)
		K.UNARY:
			return GcEngine.unary_allowed_in(command["a"], calc.mode)
		K.CLEAR_HISTORY, K.ANS:
			return not calc.history.is_empty()
		K.RECALL:
			return command["a"] < calc.history.size()
	return true


## Runs a command; returns {"persist": bool, "copy": null|String, "quit": bool}.
func dispatch(command: Dictionary) -> Dictionary:
	var effect := {"persist": false, "copy": null, "quit": false}
	if not enabled(command):
		return effect
	var K := GcCommands.Kind
	match command["k"]:
		K.DIGIT:
			calc.input_digit(command["a"])
		K.DOT:
			calc.input_dot()
		K.BINARY:
			calc.input_binary(command["a"])
		K.UNARY:
			calc.input_unary(command["a"])
		K.PERCENT:
			calc.input_percent()
		K.EQUALS:
			effect["persist"] = calc.equals() != null
		K.BACKSPACE:
			calc.backspace()
		K.CLEAR_ENTRY:
			calc.clear_entry()
		K.CLEAR_ALL:
			calc.clear_all()
		K.TOGGLE_SIGN:
			calc.toggle_sign()
		K.SET_BASE:
			calc.set_base(command["a"])
		K.TOGGLE_ANGLE:
			calc.toggle_angle()
			effect["persist"] = true
		K.LPAREN:
			calc.input_lparen()
		K.RPAREN:
			calc.input_rparen()
		K.RECALL:
			calc.recall_history(command["a"])
		K.CLEAR_HISTORY:
			calc.clear_history()
			effect["persist"] = true
		K.SET_MODE:
			effect["persist"] = command["a"] != calc.mode
			calc.set_mode(command["a"])
		K.ANS:
			calc.input_ans()
		K.EXP:
			calc.input_exp()
		K.CONSTANT:
			calc.input_const(command["a"])
		K.COPY:
			effect["copy"] = calc.result_display()
		K.TOGGLE_HISTORY:
			history_open = not history_open
		K.SHOW_DIALOG:
			dialog = command["a"]
		K.CLOSE_DIALOG:
			dialog = Dialog.NONE
		K.SET_THEME:
			effect["persist"] = command["a"] != theme
			theme = command["a"]
		K.SET_WINDOW:
			var w: Dictionary = command["a"]
			effect["persist"] = not _same_window(w, window)
			window = bounded_window(w)
		K.DISMISS_NOTICE:
			notice = null
		K.QUIT:
			effect["quit"] = true
	return effect


static func _same_window(a: Dictionary, b: Dictionary) -> bool:
	return a.get("width") == b.get("width") and a.get("height") == b.get("height") \
			and a.get("maximized") == b.get("maximized")
