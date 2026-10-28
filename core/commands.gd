class_name GcCommands
extends RefCounted
## The command boundary shared by all UI entry points and tests.
##
## A command is a Dictionary {"k": Kind, "a": argument}; build them with the
## static constructors below so call sites read like the Rust `Command` enum.

enum Kind {
	DIGIT, DOT, BINARY, UNARY, PERCENT, EQUALS, BACKSPACE, CLEAR_ENTRY, CLEAR_ALL,
	TOGGLE_SIGN, SET_BASE, TOGGLE_ANGLE, LPAREN, RPAREN, RECALL, CLEAR_HISTORY,
	SET_MODE, ANS, EXP, CONSTANT, COPY, TOGGLE_HISTORY, SHOW_DIALOG, CLOSE_DIALOG,
	SET_THEME, SET_WINDOW, DISMISS_NOTICE, QUIT,
}


static func make(kind: Kind, arg: Variant = null) -> Dictionary:
	return {"k": kind, "a": arg}


static func digit(d: int) -> Dictionary: return make(Kind.DIGIT, d)
static func dot() -> Dictionary: return make(Kind.DOT)
static func binary(op: GcEngine.BinOp) -> Dictionary: return make(Kind.BINARY, op)
static func unary(op: GcEngine.UnaryOp) -> Dictionary: return make(Kind.UNARY, op)
static func percent() -> Dictionary: return make(Kind.PERCENT)
static func equals() -> Dictionary: return make(Kind.EQUALS)
static func backspace() -> Dictionary: return make(Kind.BACKSPACE)
static func clear_entry() -> Dictionary: return make(Kind.CLEAR_ENTRY)
static func clear_all() -> Dictionary: return make(Kind.CLEAR_ALL)
static func toggle_sign() -> Dictionary: return make(Kind.TOGGLE_SIGN)
static func set_base(b: GcEngine.Base) -> Dictionary: return make(Kind.SET_BASE, b)
static func toggle_angle() -> Dictionary: return make(Kind.TOGGLE_ANGLE)
static func lparen() -> Dictionary: return make(Kind.LPAREN)
static func rparen() -> Dictionary: return make(Kind.RPAREN)
static func recall(i: int) -> Dictionary: return make(Kind.RECALL, i)
static func clear_history() -> Dictionary: return make(Kind.CLEAR_HISTORY)
static func set_mode(m: GcEngine.Mode) -> Dictionary: return make(Kind.SET_MODE, m)
static func ans() -> Dictionary: return make(Kind.ANS)
static func exp() -> Dictionary: return make(Kind.EXP)
static func constant(c: GcEngine.Const) -> Dictionary: return make(Kind.CONSTANT, c)
static func copy() -> Dictionary: return make(Kind.COPY)
static func toggle_history() -> Dictionary: return make(Kind.TOGGLE_HISTORY)
static func show_dialog(d: GcAppState.Dialog) -> Dictionary: return make(Kind.SHOW_DIALOG, d)
static func close_dialog() -> Dictionary: return make(Kind.CLOSE_DIALOG)
static func set_theme(t: GcAppState.ThemePref) -> Dictionary: return make(Kind.SET_THEME, t)
static func set_window(w: Dictionary) -> Dictionary: return make(Kind.SET_WINDOW, w)
static func dismiss_notice() -> Dictionary: return make(Kind.DISMISS_NOTICE)
static func quit() -> Dictionary: return make(Kind.QUIT)


static func is_kind(command: Variant, kind: Kind) -> bool:
	return command != null and command["k"] == kind


## `key` is the modified logical character (like DOM KeyboardEvent.key), never
## the physical/unmodified key. Platform code decides Ctrl versus Command.
## Returns a command or null.
static func keyboard(key: String, primary: bool, alt: bool, mode: GcEngine.Mode, base: GcEngine.Base) -> Variant:
	if primary:
		match key.to_lower():
			"c", "insert":
				return copy()
			"h":
				return toggle_history()
			",":
				return show_dialog(GcAppState.Dialog.SETTINGS)
			"q":
				return quit()
			"1":
				return set_mode(GcEngine.Mode.STANDARD)
			"2":
				return set_mode(GcEngine.Mode.SCIENTIFIC)
			"3":
				return set_mode(GcEngine.Mode.PROGRAMMER)
			_:
				return null
	if alt:
		return null
	match key:
		"Enter", "=":
			return equals()
		"Escape":
			return clear_all()
		"Delete":
			return clear_entry()
		"Backspace":
			return backspace()
		".", ",":
			return dot()
		"+":
			return binary(GcEngine.BinOp.ADD)
		"-":
			return binary(GcEngine.BinOp.SUB)
		"*":
			return binary(GcEngine.BinOp.MUL)
		"/":
			return binary(GcEngine.BinOp.DIV)
		"%":
			return percent()
		"^":
			return binary(GcEngine.BinOp.XOR if mode == GcEngine.Mode.PROGRAMMER else GcEngine.BinOp.POW)
		"(":
			return lparen()
		")":
			return rparen()
		"!":
			return unary(GcEngine.UnaryOp.FACT)
		"~":
			return unary(GcEngine.UnaryOp.NOT)
		"&":
			return binary(GcEngine.BinOp.AND)
		"|":
			return binary(GcEngine.BinOp.OR)
		"<":
			return binary(GcEngine.BinOp.SHL)
		">":
			return binary(GcEngine.BinOp.SHR)
		"p", "P":
			if mode == GcEngine.Mode.SCIENTIFIC:
				return constant(GcEngine.Const.PI)
			return null
		"h", "H":
			return toggle_history()
		"F1":
			return show_dialog(GcAppState.Dialog.SHORTCUTS)
	# a single ASCII hex digit
	if key.length() != 1:
		return null
	var c := key.unicode_at(0)
	var digit_value: int
	if c >= 48 and c <= 57:
		digit_value = c - 48
	elif c >= 65 and c <= 70:
		digit_value = c - 55
	elif c >= 97 and c <= 102:
		digit_value = c - 87
	else:
		return null
	if digit_value >= 10 and (mode != GcEngine.Mode.PROGRAMMER or base != GcEngine.Base.HEX):
		return null
	return digit(digit_value)
