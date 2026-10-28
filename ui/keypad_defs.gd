class_name GcKeypadDefs
extends RefCounted
## Key labels, accessible names and commands for each mode (port of keypad.rs).
## A key is {"label", "name", "command", "kind"}; kind is "digit", "function" or
## "equals". Programmer mode's "=" spans two columns.

const E := preload("res://core/engine.gd")
const C := preload("res://core/commands.gd")

const _DIGIT_LABELS := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]


static func _key(label: String, key_name: String, command: Dictionary) -> Dictionary:
	var kind := "function"
	if command["k"] == C.Kind.EQUALS:
		kind = "equals"
	elif command["k"] == C.Kind.DIGIT:
		kind = "digit"
	return {"label": label, "name": key_name, "command": command, "kind": kind}


static func _digit(d: int) -> Dictionary:
	return _key(_DIGIT_LABELS[d], _DIGIT_LABELS[d], C.digit(d))


static func _clear_keys() -> Array:
	return [
		_key("CE", "Clear entry", C.clear_entry()),
		_key("C", "Clear calculation", C.clear_all()),
		_key("⌫", "Backspace", C.backspace()),
	]


static func standard() -> Array:
	var clear := _clear_keys()
	return [
		_key("%", "Percent", C.percent()),
		clear[0], clear[1], clear[2],
		_key("1/x", "Reciprocal", C.unary(E.UnaryOp.RECIP)),
		_key("x²", "Square", C.unary(E.UnaryOp.SQUARE)),
		_key("√", "Square root", C.unary(E.UnaryOp.SQRT)),
		_key("÷", "Divide", C.binary(E.BinOp.DIV)),
		_digit(7), _digit(8), _digit(9),
		_key("×", "Multiply", C.binary(E.BinOp.MUL)),
		_digit(4), _digit(5), _digit(6),
		_key("−", "Subtract", C.binary(E.BinOp.SUB)),
		_digit(1), _digit(2), _digit(3),
		_key("+", "Add", C.binary(E.BinOp.ADD)),
		_key("±", "Toggle sign", C.toggle_sign()),
		_digit(0),
		_key(".", "Decimal point", C.dot()),
		_key("=", "Equals", C.equals()),
	]


## The scientific function panel (24 keys).
static func scientific_functions() -> Array:
	return [
		_key("x²", "Square", C.unary(E.UnaryOp.SQUARE)),
		_key("x³", "Cube", C.unary(E.UnaryOp.CUBE)),
		_key("xʸ", "Power", C.binary(E.BinOp.POW)),
		_key("y√x", "Nth root", C.binary(E.BinOp.YROOT)),
		_key("√", "Square root", C.unary(E.UnaryOp.SQRT)),
		_key("∛", "Cube root", C.unary(E.UnaryOp.CBRT)),
		_key("1/x", "Reciprocal", C.unary(E.UnaryOp.RECIP)),
		_key("x!", "Factorial", C.unary(E.UnaryOp.FACT)),
		_key("sin", "Sine", C.unary(E.UnaryOp.SIN)),
		_key("cos", "Cosine", C.unary(E.UnaryOp.COS)),
		_key("tan", "Tangent", C.unary(E.UnaryOp.TAN)),
		_key("ln", "Natural logarithm", C.unary(E.UnaryOp.LN)),
		_key("sin⁻¹", "Inverse sine", C.unary(E.UnaryOp.ASIN)),
		_key("cos⁻¹", "Inverse cosine", C.unary(E.UnaryOp.ACOS)),
		_key("tan⁻¹", "Inverse tangent", C.unary(E.UnaryOp.ATAN)),
		_key("log", "Logarithm", C.unary(E.UnaryOp.LOG10)),
		_key("eˣ", "Exponential", C.unary(E.UnaryOp.EXP)),
		_key("10ˣ", "Power of ten", C.unary(E.UnaryOp.POW10)),
		_key("π", "Pi", C.constant(E.Const.PI)),
		_key("e", "Euler's number", C.constant(E.Const.E)),
		_key("DEG/RAD", "Toggle angle unit", C.toggle_angle()),
		_key("|x|", "Absolute value", C.unary(E.UnaryOp.ABS)),
		_key("EE", "Scientific notation", C.exp()),
		_key("Ans", "Last answer", C.ans()),
	]


## The scientific numeric panel (23 keys; the 24th cell stays empty).
static func scientific_numeric() -> Array:
	var std := standard()
	var clear := _clear_keys()
	return [
		clear[0], clear[1], clear[2], std[7],
		_digit(7), _digit(8), _digit(9), std[11],
		_digit(4), _digit(5), _digit(6), std[15],
		_digit(1), _digit(2), _digit(3), std[19],
		std[20], _digit(0), std[22], std[23],
		_key("(", "Open parenthesis", C.lparen()),
		_key(")", "Close parenthesis", C.rparen()),
		_key("%", "Percent", C.percent()),
	]


static func programmer() -> Array:
	var std := standard()
	var clear := _clear_keys()
	return [
		_digit(10), _digit(11), _digit(12), _digit(13), _digit(14), _digit(15),
		_key("<<", "Shift left", C.binary(E.BinOp.SHL)),
		_key(">>", "Shift right", C.binary(E.BinOp.SHR)),
		_key("AND", "Bitwise AND", C.binary(E.BinOp.AND)),
		_key("OR", "Bitwise OR", C.binary(E.BinOp.OR)),
		_key("XOR", "Bitwise XOR", C.binary(E.BinOp.XOR)),
		_key("NOT", "Bitwise NOT", C.unary(E.UnaryOp.NOT)),
		_key("(", "Open parenthesis", C.lparen()),
		_key(")", "Close parenthesis", C.rparen()),
		_key("mod", "Modulo", C.percent()),
		clear[0], clear[1], clear[2],
		_digit(7), _digit(8), _digit(9),
		_key("±", "Toggle sign", C.toggle_sign()),
		std[7], std[11],
		_digit(4), _digit(5), _digit(6),
		_digit(0),
		std[15], std[19],
		_digit(1), _digit(2), _digit(3),
		_key("Ans", "Last answer", C.ans()),
		_key("=", "Equals", C.equals()),
	]
