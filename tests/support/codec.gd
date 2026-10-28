class_name GcTestCodec
extends RefCounted
## Text encoding of commands and state snapshots shared with the golden corpus.
##
## The corpus (tests/golden) was recorded from the Rust implementation of
## Gosh Calc 0.2: each step is a command string and the expected canonical
## snapshot of the whole application state after it ran.

const FNV_OFFSET := -3750763034362895579 # 0xcbf29ce484222325 as signed 64-bit
const FNV_PRIME := 0x100000001b3

const BINOPS := {
	"Add": GcEngine.BinOp.ADD, "Sub": GcEngine.BinOp.SUB, "Mul": GcEngine.BinOp.MUL,
	"Div": GcEngine.BinOp.DIV, "Mod": GcEngine.BinOp.MOD, "Pow": GcEngine.BinOp.POW,
	"YRoot": GcEngine.BinOp.YROOT, "Shl": GcEngine.BinOp.SHL, "Shr": GcEngine.BinOp.SHR,
	"And": GcEngine.BinOp.AND, "Or": GcEngine.BinOp.OR, "Xor": GcEngine.BinOp.XOR,
}
const UNOPS := {
	"Square": GcEngine.UnaryOp.SQUARE, "Cube": GcEngine.UnaryOp.CUBE, "Sqrt": GcEngine.UnaryOp.SQRT,
	"Cbrt": GcEngine.UnaryOp.CBRT, "Recip": GcEngine.UnaryOp.RECIP, "Fact": GcEngine.UnaryOp.FACT,
	"Sin": GcEngine.UnaryOp.SIN, "Cos": GcEngine.UnaryOp.COS, "Tan": GcEngine.UnaryOp.TAN,
	"Asin": GcEngine.UnaryOp.ASIN, "Acos": GcEngine.UnaryOp.ACOS, "Atan": GcEngine.UnaryOp.ATAN,
	"Ln": GcEngine.UnaryOp.LN, "Log10": GcEngine.UnaryOp.LOG10, "Exp": GcEngine.UnaryOp.EXP,
	"Pow10": GcEngine.UnaryOp.POW10, "Not": GcEngine.UnaryOp.NOT, "Abs": GcEngine.UnaryOp.ABS,
}
const MODES := {
	"Standard": GcEngine.Mode.STANDARD, "Scientific": GcEngine.Mode.SCIENTIFIC,
	"Programmer": GcEngine.Mode.PROGRAMMER,
}
const BASES := {
	"Hex": GcEngine.Base.HEX, "Dec": GcEngine.Base.DEC, "Oct": GcEngine.Base.OCT,
	"Bin": GcEngine.Base.BIN,
}
const DIALOGS := {
	"Settings": GcAppState.Dialog.SETTINGS, "About": GcAppState.Dialog.ABOUT,
	"Shortcuts": GcAppState.Dialog.SHORTCUTS,
}
const THEMES := {
	"system": GcAppState.ThemePref.SYSTEM, "light": GcAppState.ThemePref.LIGHT, "dark": GcAppState.ThemePref.DARK,
}


static func parse_command(s: String) -> Dictionary:
	if s.length() > 1 and s[0] == "D" and s.substr(1).is_valid_int():
		return GcCommands.digit(s.substr(1).to_int())
	var head := s
	var arg := ""
	var colon := s.find(":")
	if colon >= 0:
		head = s.substr(0, colon)
		arg = s.substr(colon + 1)
	match head:
		"DOT": return GcCommands.dot()
		"BIN": return GcCommands.binary(BINOPS[arg])
		"UN": return GcCommands.unary(UNOPS[arg])
		"PCT": return GcCommands.percent()
		"EQ": return GcCommands.equals()
		"BS": return GcCommands.backspace()
		"CE": return GcCommands.clear_entry()
		"CA": return GcCommands.clear_all()
		"SIGN": return GcCommands.toggle_sign()
		"BASE": return GcCommands.set_base(BASES[arg])
		"ANGLE": return GcCommands.toggle_angle()
		"LP": return GcCommands.lparen()
		"RP": return GcCommands.rparen()
		"RECALL": return GcCommands.recall(arg.to_int())
		"CLRH": return GcCommands.clear_history()
		"MODE": return GcCommands.set_mode(MODES[arg])
		"ANS": return GcCommands.ans()
		"EE": return GcCommands.exp()
		"CONST": return GcCommands.constant(GcEngine.Const.PI if arg == "Pi" else GcEngine.Const.E)
		"COPY": return GcCommands.copy()
		"THIST": return GcCommands.toggle_history()
		"DLG": return GcCommands.show_dialog(DIALOGS[arg])
		"CLOSE": return GcCommands.close_dialog()
		"THEME": return GcCommands.set_theme(THEMES[arg])
		"WIN":
			var p := arg.split(",")
			return GcCommands.set_window({
				"width": GcNum.parse_f64(p[0]), "height": GcNum.parse_f64(p[1]),
				"maximized": p[2] == "1",
			})
		"DISMISS": return GcCommands.dismiss_notice()
		"QUIT": return GcCommands.quit()
	push_error("unknown command string: " + s)
	return GcCommands.make(-1)


static func command_name(c: Variant) -> Variant:
	if c == null:
		return null
	var K := GcCommands.Kind
	match c["k"]:
		K.DIGIT: return "D%d" % c["a"]
		K.DOT: return "DOT"
		K.BINARY: return "BIN:" + BINOPS.find_key(c["a"])
		K.UNARY: return "UN:" + UNOPS.find_key(c["a"])
		K.PERCENT: return "PCT"
		K.EQUALS: return "EQ"
		K.BACKSPACE: return "BS"
		K.CLEAR_ENTRY: return "CE"
		K.CLEAR_ALL: return "CA"
		K.TOGGLE_SIGN: return "SIGN"
		K.SET_BASE: return "BASE:" + BASES.find_key(c["a"])
		K.TOGGLE_ANGLE: return "ANGLE"
		K.LPAREN: return "LP"
		K.RPAREN: return "RP"
		K.RECALL: return "RECALL:%d" % c["a"]
		K.CLEAR_HISTORY: return "CLRH"
		K.SET_MODE: return "MODE:" + MODES.find_key(c["a"])
		K.ANS: return "ANS"
		K.EXP: return "EE"
		K.CONSTANT: return "CONST:" + ("Pi" if c["a"] == GcEngine.Const.PI else "E")
		K.COPY: return "COPY"
		K.TOGGLE_HISTORY: return "THIST"
		K.SHOW_DIALOG: return "DLG:" + DIALOGS.find_key(c["a"])
		K.CLOSE_DIALOG: return "CLOSE"
		K.SET_THEME: return "THEME:" + THEMES.find_key(c["a"])
		K.SET_WINDOW: return "WIN"
		K.DISMISS_NOTICE: return "DISMISS"
		K.QUIT: return "QUIT"
	return "?"


static func hex64(v: int) -> String:
	var s := ""
	for i in range(15, -1, -1):
		s += "0123456789abcdef"[(v >> (i * 4)) & 0xF]
	return s


## "F:<ieee bits>" / "I:<n>" / "-" for a history value.
static func value_token(v: Variant) -> String:
	if v == null:
		return "-"
	if typeof(v) == TYPE_INT:
		return "I:%d" % v
	return "F:" + hex64(GcNum.bits_of(v))


static func _fnv(h: int, s: String) -> int:
	for b in s.to_utf8_buffer():
		h = (h ^ b) * FNV_PRIME
	return (h ^ 0xff) * FNV_PRIME


static func canon(app: GcAppState, enabled: bool, effect: Dictionary) -> String:
	var c := app.calc
	var h := FNV_OFFSET
	for e in c.history:
		h = _fnv(h, e["expr"])
		h = _fnv(h, e["result"])
		h = _fnv(h, value_token(e["value"]))
	var readout: Variant = c.base_readout()
	var copy: Variant = effect["copy"]
	var fields := PackedStringArray([
		c.result_display(),
		c.expression_display(),
		c.entry(),
		"-" if c.error == GcEngine.CalcError.NONE else GcEngine.error_message(c.error),
		"-" if readout == null else ",".join(PackedStringArray(readout)),
		GcEngine.Mode.keys()[c.mode].capitalize(),
		GcEngine.Base.keys()[c.base].capitalize(),
		GcEngine.AngleUnit.keys()[c.angle].capitalize(),
		"1" if enabled else "0",
		"1" if effect["persist"] else "0",
		"~" if copy == null else "=" + copy,
		"1" if effect["quit"] else "0",
		"1" if app.history_open else "0",
		"-" if app.dialog == GcAppState.Dialog.NONE else GcAppState.Dialog.keys()[app.dialog].capitalize(),
		GcAppState.theme_css(app.theme),
		"%s,%s,%s" % [hex64(GcNum.bits_of(app.window["width"])), hex64(GcNum.bits_of(app.window["height"])),
				"1" if app.window["maximized"] else "0"],
		str(c.history.size()),
		hex64(h),
	])
	return "\t".join(fields)


static func history_from_request(items: Array) -> Array:
	var out := []
	for e in items:
		var v: Variant = null
		if e[2] != null:
			var tok: String = e[2]
			if tok.begins_with("F:"):
				v = GcNum.from_bits(_parse_hex64(tok.substr(2)))
			else:
				v = tok.substr(2).to_int()
		out.append({"expr": e[0], "result": e[1], "value": v})
	return out


static func _parse_hex64(s: String) -> int:
	var r := 0
	for ch in s:
		r = (r << 4) | "0123456789abcdef".find(ch)
	return r


## Runs one request (sequence/key/fmt) and returns the actual response in the
## same JSON shape the Rust oracle produced.
static func run_request(req: Dictionary) -> Variant:
	if req.has("key"):
		return command_name(GcCommands.keyboard(req["key"], req["primary"], req["alt"],
				MODES[req["mode"]], BASES[req["base"]]))
	var app := GcAppState.new()
	if req.has("history"):
		app.calc.history = history_from_request(req["history"])
	var steps := []
	for s in req["seq"]:
		var command := parse_command(s)
		var enabled := app.enabled(command)
		var effect := app.dispatch(command)
		steps.append(canon(app, enabled, effect))
	return steps
