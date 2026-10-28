class_name GcEngine
extends RefCounted
## Portable calculator engine; independent of the UI and operating system.
##
## Immediate-execution model: the user builds a token list (`_expr`) plus a raw
## `_entry` string for the operand being typed. `equals()` evaluates the whole
## token list with correct precedence.
##
## Values are GDScript Variants: an `int` is an exact signed 64-bit integer
## (programmer mode) and a `float` is an IEEE binary64 (standard/scientific).
## Behaviour is a faithful port of the Rust engine in Gosh Calc 0.2.

enum Mode { STANDARD, SCIENTIFIC, PROGRAMMER }
enum AngleUnit { DEG, RAD }
enum Base { HEX, DEC, OCT, BIN }
enum BinOp { ADD, SUB, MUL, DIV, MOD, POW, YROOT, SHL, SHR, AND, OR, XOR }
enum UnaryOp {
	SQUARE, CUBE, SQRT, CBRT, RECIP, FACT, SIN, COS, TAN, ASIN, ACOS, ATAN,
	LN, LOG10, EXP, POW10, NOT, ABS,
}
enum Const { PI, E }
enum CalcError { NONE, DIV_BY_ZERO, OVERFLOW, DOMAIN, INVALID_EXPR, OUT_OF_RANGE }

const MAX_ENTRY_LEN := 32
const MAX_TOKENS := 256
const MAX_HISTORY := 100
## Bound for any single persisted string (history expr/result) accepted from
## the settings file. Engine-formatted values are far shorter; this only bites
## on hostile or rotted data.
const MAX_PERSIST_STR := 256

const INT_MAX := 9223372036854775807
const INT_MIN := -9223372036854775807 - 1

const _T_VAL := 0
const _T_OP := 1
const _T_LPAREN := 2
const _T_RPAREN := 3

const _DIGITS := "0123456789ABCDEF"

## IEEE bit patterns of std::f64::consts::PI and E (exact, unlike literals).
const _PI_BITS := 0x400921FB54442D18
const _E_BITS := 0x4005BF0A8B145769

static var _pi := GcNum.from_bits(_PI_BITS)
static var _e := GcNum.from_bits(_E_BITS)
static var _trig_epsilon: float = GcNum.parse_f64("1e-12")
static var _rad_per_deg: float = _pi / 180.0
static var _deg_per_rad: float = 180.0 / _pi
static var _int_clamp: float = float(9000000000000000000)

var mode: Mode = Mode.STANDARD
var angle: AngleUnit = AngleUnit.DEG
var base: Base = Base.DEC
var error: CalcError = CalcError.NONE
## Newest first. Entries are {"expr": String, "result": String, "value": null|int|float}.
var history: Array = []

var _expr: Array = [] # tokens: [kind, payload]
var _entry := ""
var _repeat: Variant = null # [BinOp, value]: last binary op and right operand
var _fresh := true # entry starts fresh on next digit (post-op, post-=)
var _evaluated := false # set right after a successful `=` while entry holds the result


# ---------- enum metadata ----------

static func radix_of(b: Base) -> int:
	match b:
		Base.HEX:
			return 16
		Base.DEC:
			return 10
		Base.OCT:
			return 8
		_:
			return 2


static func base_label(b: Base) -> String:
	match b:
		Base.HEX:
			return "HEX"
		Base.DEC:
			return "DEC"
		Base.OCT:
			return "OCT"
		_:
			return "BIN"


static func digit_valid(b: Base, d: int) -> bool:
	return d < radix_of(b)


static func binop_precedence(op: BinOp) -> int:
	match op:
		BinOp.POW, BinOp.YROOT:
			return 5
		BinOp.MUL, BinOp.DIV, BinOp.MOD:
			return 4
		BinOp.ADD, BinOp.SUB:
			return 3
		BinOp.SHL, BinOp.SHR:
			return 2
		BinOp.AND:
			return 1
		_:
			return 0


## Only Pow/YRoot are right-associative (2^3^2 = 2^9).
static func binop_right_assoc(op: BinOp) -> bool:
	return op == BinOp.POW or op == BinOp.YROOT


static func binop_symbol(op: BinOp) -> String:
	match op:
		BinOp.ADD:
			return "+"
		BinOp.SUB:
			return "−"
		BinOp.MUL:
			return "×"
		BinOp.DIV:
			return "÷"
		BinOp.MOD:
			return "mod"
		BinOp.POW:
			return "^"
		BinOp.YROOT:
			return "y√"
		BinOp.SHL:
			return "<<"
		BinOp.SHR:
			return ">>"
		BinOp.AND:
			return "&"
		BinOp.OR:
			return "|"
		_:
			return "xor"


static func binop_allowed_in(op: BinOp, m: Mode) -> bool:
	match op:
		BinOp.MOD, BinOp.SHL, BinOp.SHR, BinOp.AND, BinOp.OR, BinOp.XOR:
			return m == Mode.PROGRAMMER
		_:
			return true


static func unary_allowed_in(op: UnaryOp, m: Mode) -> bool:
	match op:
		UnaryOp.NOT:
			return m == Mode.PROGRAMMER
		UnaryOp.SQUARE, UnaryOp.CUBE, UnaryOp.SQRT, UnaryOp.CBRT, UnaryOp.RECIP, \
		UnaryOp.FACT, UnaryOp.ABS:
			return m != Mode.PROGRAMMER
		_:
			return m == Mode.SCIENTIFIC


static func error_message(e: CalcError) -> String:
	match e:
		CalcError.DIV_BY_ZERO:
			return "Division by zero"
		CalcError.OVERFLOW:
			return "Overflow"
		CalcError.DOMAIN:
			return "Domain error"
		CalcError.INVALID_EXPR:
			return "Invalid expression"
		CalcError.OUT_OF_RANGE:
			return "Value out of range"
		_:
			return ""


# ---------- value helpers ----------

static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _as_f64(v: Variant) -> float:
	return float(v)


## Rust `as i64`: saturating, NaN becomes 0.
static func _as_i64(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return v
	var f: float = v
	if is_nan(f):
		return 0
	if f >= 9223372036854775807.0:
		return INT_MAX
	if f <= -9223372036854775808.0:
		return INT_MIN
	return int(f)


static func _utf8_len(s: String) -> int:
	var n := 0
	for i in s.length():
		var c := s.unicode_at(i)
		n += 1 if c < 0x80 else (2 if c < 0x800 else (3 if c < 0x10000 else 4))
	return n


## Truncate to at most `max_bytes` UTF-8 bytes on a character boundary.
static func truncate_str(s: String, max_bytes: int) -> String:
	if _utf8_len(s) <= max_bytes:
		return s
	var used := 0
	var keep := 0
	for i in s.length():
		var c := s.unicode_at(i)
		var w := 1 if c < 0x80 else (2 if c < 0x800 else (3 if c < 0x10000 else 4))
		if used + w > max_bytes:
			break
		used += w
		keep = i + 1
	return s.substr(0, keep)


## Value formatting for unsigned radix output (two's complement for negatives).
static func _u64_to_radix(v: int, bits: int) -> String:
	if v == 0:
		return "0"
	var mask := (1 << bits) - 1
	var keep := (1 << (64 - bits)) - 1 # turns the arithmetic shift into a logical one
	var out := ""
	while v != 0:
		out = _DIGITS[v & mask] + out
		v = (v >> bits) & keep
	return out


## Rust `str::parse::<i64>`; returns null on error or overflow.
static func _parse_i64(s: String) -> Variant:
	var i := 0
	var neg := false
	if s.length() > 0 and (s[0] == "-" or s[0] == "+"):
		neg = s[0] == "-"
		i = 1
	if i >= s.length():
		return null
	var acc := 0 # accumulated as a non-positive number so INT_MIN fits
	while i < s.length():
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			return null
		var d := c - 48
		if acc < (INT_MIN + d) / 10:
			return null
		acc = acc * 10 - d
		i += 1
	if neg:
		return acc
	if acc == INT_MIN:
		return null
	return -acc


## Rust `u64::from_str_radix` for radix 2, 8, 16; returns the bit pattern as an
## int, or null on error or overflow.
static func _parse_u64(s: String, radix: int) -> Variant:
	var i := 0
	if s.length() > 0 and s[0] == "+":
		i = 1
	if i >= s.length():
		return null
	var bits := 4 if radix == 16 else (3 if radix == 8 else 1)
	var mask := (1 << bits) - 1
	var acc := 0
	while i < s.length():
		var c := s.unicode_at(i)
		var d: int
		if c >= 48 and c <= 57:
			d = c - 48
		elif c >= 65 and c <= 70:
			d = c - 55
		elif c >= 97 and c <= 102:
			d = c - 87
		else:
			return null
		if d >= radix:
			return null
		if ((acc >> (64 - bits)) & mask) != 0:
			return null # would shift a set bit out of 64
		acc = (acc << bits) | d
		i += 1
	return acc


# ---------- checked integer arithmetic (Rust checked_*) ----------

static func _checked_add(a: int, b: int) -> Variant:
	var r := a + b
	if ((a ^ r) & (b ^ r)) < 0:
		return null
	return r


static func _checked_sub(a: int, b: int) -> Variant:
	var r := a - b
	if ((a ^ b) & (a ^ r)) < 0:
		return null
	return r


static func _checked_mul(a: int, b: int) -> Variant:
	if a == 0 or b == 0:
		return 0
	if (a == -1 and b == INT_MIN) or (b == -1 and a == INT_MIN):
		return null
	var r := a * b
	if r / b != a:
		return null
	return r


static func _checked_pow(base_: int, exp_: int) -> Variant:
	if exp_ == 0:
		return 1
	var acc := 1
	var b := base_
	while exp_ > 1:
		if (exp_ & 1) == 1:
			var m = _checked_mul(acc, b)
			if m == null:
				return null
			acc = m
		exp_ >>= 1
		var sq = _checked_mul(b, b)
		if sq == null:
			return null
		b = sq
	return _checked_mul(acc, b)


# ---------- queries ----------

func entry() -> String:
	return _entry


## What the small expression line should show: committed tokens plus the
## in-progress entry. Empty when nothing has been typed.
func expression_display() -> String:
	var s := ""
	for t in _expr:
		s += _token_display(t)
	if not _expr.is_empty() or _evaluated:
		# show the raw in-progress operand as typed
		if not _entry.is_empty() and not _evaluated:
			s += _entry
	return s


## What the big result line shows: live evaluation when an expression is in
## progress, otherwise the raw entry (so typed states like "0." survive), "0"
## when blank.
func result_display() -> String:
	if error != CalcError.NONE:
		return "Error"
	if _evaluated or (not _entry.is_empty() and _expr.is_empty()):
		return "0" if _entry.is_empty() else _entry
	var p := _preview()
	if p[0] == CalcError.NONE:
		return fmt_value(p[1])
	if _entry.is_empty():
		return "0"
	return _entry


## Four-base readout for programmer mode: [hex, dec, oct, bin], or null.
func base_readout() -> Variant:
	if mode != Mode.PROGRAMMER:
		return null
	var cv := _current_value()
	if cv[0] != CalcError.NONE:
		return null
	var v := _as_i64(cv[1])
	return [_u64_to_radix(v, 4), str(v), _u64_to_radix(v, 3), _u64_to_radix(v, 1)]


func _token_display(t: Array) -> String:
	match t[0]:
		_T_VAL:
			return fmt_value(t[1])
		_T_OP:
			return " %s " % binop_symbol(t[1])
		_T_LPAREN:
			return "("
		_:
			return ") "


# ---------- input ----------

func input_digit(d: int) -> void:
	if error != CalcError.NONE:
		clear_all()
	if not digit_valid(base, d):
		return
	if _fresh or _evaluated:
		_entry = ""
		_fresh = false
		_evaluated = false
		# a digit after ")" or a committed value starts a new operand: commit
		# nothing, leave the expression as is (implicit multiplication is
		# intentionally not supported)
	if _utf8_len(_entry) >= MAX_ENTRY_LEN:
		return
	var c := _DIGITS[d]
	# avoid leading zeros stacking in non-hex bases
	if _entry == "0" and base != Base.HEX:
		_entry = ""
	_entry += c


func input_dot() -> void:
	if mode == Mode.PROGRAMMER or error != CalcError.NONE:
		return
	if _fresh or _evaluated:
		_entry = "0"
		_fresh = false
		_evaluated = false
	if not _entry.contains("."):
		if _entry.is_empty():
			_entry += "0"
		_entry += "."


func toggle_sign() -> void:
	if error != CalcError.NONE:
		return
	if _entry.begins_with("-"):
		_entry = _entry.substr(1)
	elif mode == Mode.PROGRAMMER:
		# two's-complement negate of the current value
		var cv := _current_value()
		if cv[0] == CalcError.NONE:
			var n := _as_i64(cv[1])
			_entry = fmt_value(0 - n if n != INT_MIN else INT_MIN)
			_fresh = false
	else:
		if _entry.is_empty():
			_entry = "0"
			_fresh = false
			_evaluated = false
		_entry = "-" + _entry


func backspace() -> void:
	if error != CalcError.NONE:
		error = CalcError.NONE
		return
	if _evaluated:
		return
	if not _entry.is_empty():
		_entry = _entry.substr(0, _entry.length() - 1)
	_fresh = false


func clear_entry() -> void:
	_entry = ""
	error = CalcError.NONE
	_fresh = true
	_evaluated = false


func clear_all() -> void:
	_expr.clear()
	_entry = ""
	error = CalcError.NONE
	_fresh = true
	_evaluated = false
	_repeat = null


## `EE`: begin an exponent for scientific-notation input ("5e3").
func input_exp() -> void:
	if mode == Mode.PROGRAMMER or error != CalcError.NONE:
		return
	if _fresh or _evaluated:
		_entry = "1"
		_fresh = false
		_evaluated = false
	# only after digits/sign, and only one exponent marker
	if _entry.is_empty() or _entry.ends_with("e") or _entry.ends_with("E"):
		return
	if not (_entry.contains("e") or _entry.contains("E")) and _has_ascii_digit(_entry):
		_entry += "e"


static func _has_ascii_digit(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 48 and c <= 57:
			return true
	return false


## `Ans`: recall the most recent result into the entry.
func input_ans() -> void:
	if error != CalcError.NONE:
		return
	recall_history(0)


func input_const(c: Const) -> void:
	if mode == Mode.PROGRAMMER or error != CalcError.NONE:
		return
	_entry = GcNum.fmt_f64(_pi if c == Const.PI else _e)
	_fresh = false
	_evaluated = false


func input_binary(op: BinOp) -> void:
	if error != CalcError.NONE or not binop_allowed_in(op, mode):
		return
	if _expr.size() >= MAX_TOKENS - 2:
		error = CalcError.OUT_OF_RANGE
		return
	# "-" while typing a negative operand: wait for digits
	if _entry == "-":
		return
	if _entry.is_empty():
		var last: Variant = null if _expr.is_empty() else _expr.back()
		var kind: int = -1 if last == null else last[0]
		if (kind == _T_OP or kind == _T_LPAREN) and op == BinOp.SUB:
			# unary minus: "2 × − 3": start a negative operand
			_entry = "-"
			_fresh = false
			_evaluated = false
			return
		if kind == _T_LPAREN:
			return # "(" followed by a non-minus operator is invalid
		if kind == _T_OP:
			_expr[_expr.size() - 1] = [_T_OP, op] # op correction: "2 + ×" -> "2 ×"
			return
		if last == null:
			if op == BinOp.SUB:
				# leading "-" signs
				_entry = "-"
				_fresh = false
				_evaluated = false
				return
			_expr.append([_T_VAL, _zero()]) # "×" starts "0 ×"
		# value or ")" committed already: fine
	else:
		var p := _parse_entry()
		if p[0] != CalcError.NONE:
			error = p[0]
			return
		_expr.append([_T_VAL, p[1]])
	_entry = ""
	_expr.append([_T_OP, op])
	_fresh = true
	_evaluated = false


func input_lparen() -> void:
	if error != CalcError.NONE or mode == Mode.STANDARD:
		return
	if _expr.size() >= MAX_TOKENS / 2:
		error = CalcError.OUT_OF_RANGE
		return
	# "(" mid-entry would need implicit multiplication, which is not supported
	if not _fresh and not _entry.is_empty():
		return
	# "(" only valid after an operator, "(", or at the start
	if not _expr.is_empty() and (_expr.back()[0] == _T_VAL or _expr.back()[0] == _T_RPAREN):
		return
	_entry = ""
	_expr.append([_T_LPAREN])
	_fresh = true
	_evaluated = false


func input_rparen() -> void:
	if error != CalcError.NONE or mode == Mode.STANDARD:
		return
	# commit pending entry
	if not _entry.is_empty():
		var p := _parse_entry()
		if p[0] != CalcError.NONE:
			error = p[0]
			return
		_expr.append([_T_VAL, p[1]])
		_entry = ""
	var opens := 0
	var closes := 0
	for t in _expr:
		if t[0] == _T_LPAREN:
			opens += 1
		elif t[0] == _T_RPAREN:
			closes += 1
	if opens <= closes:
		return
	# ")" right after "(" or an operator is invalid
	if not _expr.is_empty() and (_expr.back()[0] == _T_LPAREN or _expr.back()[0] == _T_OP):
		return
	_expr.append([_T_RPAREN])
	_fresh = true


func input_unary(op: UnaryOp) -> void:
	if error != CalcError.NONE or not unary_allowed_in(op, mode):
		return
	var cv := _current_value()
	if cv[0] != CalcError.NONE:
		error = cv[0]
		return
	var r := _apply_unary(op, cv[1])
	if r[0] == CalcError.NONE:
		_entry = fmt_value(r[1])
		_fresh = false
		_evaluated = false
	else:
		error = r[0]


func input_percent() -> void:
	if error != CalcError.NONE:
		return
	if mode == Mode.PROGRAMMER:
		input_binary(BinOp.MOD)
		return
	var cv := _current_value()
	if cv[0] != CalcError.NONE:
		error = cv[0]
		return
	var v := _as_f64(cv[1])
	# context: value of the committed expression without a trailing op
	var ctx: Variant = _context_value()
	var pct: float
	var last: Variant = null if _expr.is_empty() else _expr.back()
	if last != null and last[0] == _T_OP and (last[1] == BinOp.ADD or last[1] == BinOp.SUB):
		pct = (float(ctx) * v / 100.0) if ctx != null else v / 100.0
	else:
		pct = v / 100.0
	_entry = GcNum.fmt_f64(pct)
	_fresh = false


## Evaluate. Returns [expr, result] for the history record on success, else null.
func equals() -> Variant:
	if error != CalcError.NONE:
		return null
	# repeat-equals: bare "=" re-applies the last binary op
	var toks := _committed_tokens()
	var repeated := false
	var result: Variant
	var has_op := false
	for t in toks:
		if t[0] == _T_OP:
			has_op = true
			break
	if toks.is_empty() or not has_op:
		var cv := _current_value()
		if cv[0] != CalcError.NONE:
			error = cv[0]
			return null
		var cur: Variant = cv[1]
		var rep: Variant = _repeat if (_evaluated or toks.is_empty()) else null
		if rep != null:
			var r := apply_binary(rep[0], cur, rep[1])
			if r[0] != CalcError.NONE:
				error = r[0]
				return null
			_expr = [[_T_VAL, cur], [_T_OP, rep[0]], [_T_VAL, rep[1]]]
			repeated = true
			result = r[1]
		else:
			result = cur
	else:
		# record repeat info: last binary op and its right operand
		_repeat = _last_binop(toks)
		var ev := eval_tokens(toks)
		if ev[0] != CalcError.NONE:
			error = ev[0]
			return null
		result = ev[1]

	var expr_str: String
	if repeated:
		expr_str = _full_expr_display(_expr.duplicate())
	elif toks.is_empty():
		expr_str = _entry
	else:
		expr_str = _full_expr_display(toks)
	var result_str := fmt_value(result)
	_entry = result_str
	_expr.clear()
	_fresh = true
	_evaluated = true

	# Bare `=` with nothing committed and no repeat applied computes nothing:
	# update the display state but do not spam history with no-op records.
	if toks.is_empty() and not repeated:
		return null

	history.push_front({"expr": expr_str, "result": result_str, "value": result})
	if history.size() > MAX_HISTORY:
		history.resize(MAX_HISTORY)
	return [expr_str, result_str]


func recall_history(idx: int) -> void:
	if idx < 0 or idx >= history.size():
		return
	var h: Dictionary = history[idx]
	var v: Variant = h.get("value")
	if v != null and mode == Mode.PROGRAMMER:
		_entry = fmt_value(_as_i64(v))
	elif v != null:
		_entry = fmt_value(_as_f64(v))
	else:
		_entry = h["result"]
	_entry = truncate_str(_entry, MAX_ENTRY_LEN)
	error = CalcError.NONE
	_fresh = true
	_evaluated = false


## Clamp data loaded from the settings file to safe bounds. The file is
## user-editable shared state, so history length and per-field strings are
## treated as untrusted input.
func sanitize_persisted() -> void:
	if history.size() > MAX_HISTORY:
		history.resize(MAX_HISTORY)
	for h in history:
		h["expr"] = truncate_str(h["expr"], MAX_PERSIST_STR)
		h["result"] = truncate_str(h["result"], MAX_PERSIST_STR)


func clear_history() -> void:
	history.clear()


# ---------- mode / base / angle ----------

func set_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		return
	# convert in-flight value between domains
	var cv := _current_value()
	var v: Variant = cv[1] if cv[0] == CalcError.NONE else _zero()
	var converted: Variant = v
	var was_prog := mode == Mode.PROGRAMMER
	var to_prog := new_mode == Mode.PROGRAMMER
	if not was_prog and to_prog:
		var f := _as_f64(v)
		converted = int(clampf(f, -_int_clamp, _int_clamp)) if is_finite(f) else 0
	elif was_prog and not to_prog:
		converted = _as_f64(v)
	mode = new_mode
	if new_mode != Mode.PROGRAMMER:
		base = Base.DEC
	for i in _expr.size():
		var t: Array = _expr[i]
		if t[0] == _T_VAL:
			_expr[i] = [_T_VAL, _as_i64(t[1]) if to_prog else _as_f64(t[1])]
	if error == CalcError.NONE:
		_entry = fmt_value(converted)
		if _entry == "0" and _expr.is_empty():
			_entry = ""
		_fresh = true
	_evaluated = false


func set_base(new_base: Base) -> void:
	if mode != Mode.PROGRAMMER or base == new_base:
		return
	# reinterpret current entry in the new base
	var cv := _current_value()
	if cv[0] == CalcError.NONE:
		base = new_base
		if error == CalcError.NONE:
			if _as_i64(cv[1]) == 0 and _entry.is_empty():
				_entry = ""
			else:
				_entry = fmt_value(cv[1])
	else:
		base = new_base


func toggle_angle() -> void:
	angle = AngleUnit.RAD if angle == AngleUnit.DEG else AngleUnit.DEG


# ---------- internals ----------

func _zero() -> Variant:
	return 0 if mode == Mode.PROGRAMMER else 0.0


static func _ok(v: Variant) -> Array:
	return [CalcError.NONE, v]


static func _fail(e: CalcError) -> Array:
	return [e, null]


## Returns [error, value].
func _parse_entry() -> Array:
	var s := _entry
	if mode == Mode.PROGRAMMER:
		if s.is_empty() or s == "-":
			return _ok(0)
		if base == Base.DEC:
			# decimal entry is a signed i64 literal
			var iv: Variant = _parse_i64(s)
			if iv == null:
				return _fail(CalcError.OUT_OF_RANGE)
			return _ok(iv)
		# non-decimal entry is a u64 bit pattern; a leading "-" (from the
		# toggle_sign display) means two's-complement negate
		var neg := s.begins_with("-")
		var digits := s
		while digits.begins_with("-"):
			digits = digits.substr(1)
		var u: Variant = _parse_u64(digits, radix_of(base))
		if u == null:
			return _fail(CalcError.OUT_OF_RANGE)
		var i: int = u
		if neg:
			i = 0 - i if i != INT_MIN else INT_MIN
		return _ok(i)
	if s.is_empty() or s == "-":
		return _ok(0.0)
	var fv: Variant = GcNum.parse_f64(s)
	if fv == null:
		return _fail(CalcError.INVALID_EXPR)
	var f: float = fv
	if is_nan(f) or is_inf(f):
		return _fail(CalcError.OVERFLOW)
	return _ok(f)


## Current operand value: entry if present, else last expr value, else 0.
## Returns [error, value].
func _current_value() -> Array:
	if not _entry.is_empty():
		return _parse_entry()
	var i := _expr.size() - 1
	while i >= 0:
		var t: Array = _expr[i]
		if t[0] == _T_VAL:
			return _ok(t[1])
		if t[0] == _T_RPAREN:
			break
		i -= 1
	return _ok(_zero())


## Value of committed tokens with any trailing operator dropped; the context
## for %. Returns null when unavailable.
func _context_value() -> Variant:
	var toks := _expr.duplicate()
	while not toks.is_empty() and toks.back()[0] == _T_OP:
		toks.pop_back()
	if toks.is_empty():
		return null
	var r := eval_tokens(toks)
	if r[0] != CalcError.NONE:
		return null
	return _as_f64(r[1])


## expr + committed entry, trailing ops dropped, parens balanced.
func _committed_tokens() -> Array:
	var toks := _expr.duplicate()
	if not _entry.is_empty() and not _evaluated:
		var p := _parse_entry()
		if p[0] == CalcError.NONE:
			toks.append([_T_VAL, p[1]])
	while not toks.is_empty() and toks.back()[0] == _T_OP:
		toks.pop_back()
	# auto-close unclosed parens
	var depth := 0
	for t in toks:
		if t[0] == _T_LPAREN:
			depth += 1
		elif t[0] == _T_RPAREN:
			depth -= 1
	for _i in maxi(depth, 0):
		toks.append([_T_RPAREN])
	return toks


func _preview() -> Array:
	var toks := _committed_tokens()
	if toks.is_empty():
		return _fail(CalcError.INVALID_EXPR)
	return eval_tokens(toks)


## Last top-level binary op and right operand for repeat-equals.
static func _last_binop(toks: Array) -> Variant:
	var depth := 0
	var last: Variant = null
	for i in toks.size():
		var t: Array = toks[i]
		if t[0] == _T_LPAREN:
			depth += 1
		elif t[0] == _T_RPAREN:
			depth -= 1
		elif t[0] == _T_OP and depth == 0:
			if i + 1 < toks.size() and toks[i + 1][0] == _T_VAL:
				last = [t[1], toks[i + 1][1]]
	return last


func _full_expr_display(toks: Array) -> String:
	var s := ""
	for t in toks:
		s += _token_display(t)
	# trim_end: Rust trims Unicode whitespace; display tokens only add ASCII spaces
	return s.rstrip(" ")


func fmt_value(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return GcNum.fmt_f64(v)
	return _fmt_int(v)


func _fmt_int(v: int) -> String:
	match base:
		Base.DEC:
			return str(v)
		Base.HEX:
			return _u64_to_radix(v, 4)
		Base.OCT:
			return _u64_to_radix(v, 3)
		_:
			return _u64_to_radix(v, 1)


# ---------- arithmetic ----------

## Returns [error, value].
func _apply_unary(op: UnaryOp, v: Variant) -> Array:
	if op == UnaryOp.NOT:
		return _ok(~_as_i64(v))
	var x := _as_f64(v)
	var r: float
	match op:
		UnaryOp.SQUARE:
			r = x * x
		UnaryOp.CUBE:
			r = x * x * x
		UnaryOp.SQRT:
			if x < 0.0:
				return _fail(CalcError.DOMAIN)
			r = sqrt(x)
		UnaryOp.CBRT:
			r = _cbrt(x)
		UnaryOp.RECIP:
			if x == 0.0:
				return _fail(CalcError.DIV_BY_ZERO)
			r = 1.0 / x
		UnaryOp.FACT:
			return _fact(x)
		UnaryOp.SIN:
			r = sin(_to_rad(angle, x))
		UnaryOp.COS:
			r = cos(_to_rad(angle, x))
		UnaryOp.TAN:
			r = tan(_to_rad(angle, x))
			if is_nan(r) or is_inf(r):
				return _fail(CalcError.DOMAIN)
		UnaryOp.ASIN:
			if not (x >= -1.0 and x <= 1.0):
				return _fail(CalcError.DOMAIN)
			r = _unit_from_rad(angle, asin(x))
		UnaryOp.ACOS:
			if not (x >= -1.0 and x <= 1.0):
				return _fail(CalcError.DOMAIN)
			r = _unit_from_rad(angle, acos(x))
		UnaryOp.ATAN:
			r = _unit_from_rad(angle, atan(x))
		UnaryOp.LN:
			if x <= 0.0:
				return _fail(CalcError.DOMAIN)
			r = log(x)
		UnaryOp.LOG10:
			if x <= 0.0:
				return _fail(CalcError.DOMAIN)
			r = _log10(x)
		UnaryOp.EXP:
			r = exp(x)
		UnaryOp.POW10:
			r = pow(10.0, x)
		UnaryOp.ABS:
			r = absf(x)
		_:
			return _fail(CalcError.DOMAIN)
	# trig results snap to zero at calculator epsilon, absorbing input
	# truncation like sin(pi) = -2e-13
	if op in [UnaryOp.SIN, UnaryOp.COS, UnaryOp.TAN, UnaryOp.ASIN, UnaryOp.ACOS, UnaryOp.ATAN] \
			and absf(r) < _trig_epsilon:
		r = 0.0
	if is_nan(r):
		return _fail(CalcError.DOMAIN)
	if is_inf(r):
		return _fail(CalcError.OVERFLOW)
	return _ok(r)


static func _fact(x: float) -> Array:
	if x < 0.0 or x != floorf(x):
		return _fail(CalcError.DOMAIN)
	if x > 170.0:
		return _fail(CalcError.OVERFLOW)
	var r := 1.0
	for i in range(2, int(x) + 1):
		r *= float(i)
	return _ok(r)


static func _to_rad(a: AngleUnit, x: float) -> float:
	return x * _rad_per_deg if a == AngleUnit.DEG else x


static func _unit_from_rad(a: AngleUnit, x: float) -> float:
	return x * _deg_per_rad if a == AngleUnit.DEG else x


## GDScript has no log10/cbrt. These derive them from log/pow and snap exact
## powers of ten / perfect cubes so common inputs stay exact.
static func _log10(x: float) -> float:
	var r := log(x) / log(10.0)
	var rounded := roundf(r)
	if absf(r - rounded) < 1e-9 and pow(10.0, rounded) == x:
		return rounded
	return r


static func _cbrt(x: float) -> float:
	if x == 0.0 or is_nan(x) or is_inf(x):
		return x
	var a := absf(x)
	var r := pow(a, 1.0 / 3.0)
	r -= (r * r * r - a) / (3.0 * r * r) # one Newton step fixes the last bits
	var rounded := roundf(r)
	if rounded * rounded * rounded == a:
		r = rounded
	return -r if x < 0.0 else r


## Returns [error, value].
static func apply_binary(op: BinOp, a: Variant, b: Variant) -> Array:
	match op:
		BinOp.AND, BinOp.OR, BinOp.XOR, BinOp.SHL, BinOp.SHR:
			var x := _as_i64(a)
			var y := _as_i64(b)
			var r: int
			match op:
				BinOp.AND:
					r = x & y
				BinOp.OR:
					r = x | y
				BinOp.XOR:
					r = x ^ y
				BinOp.SHL:
					r = _wrapping_shl(x, y)
				_:
					r = _wrapping_shr(x, y)
			return _ok(r)
	# integer path when both operands are Int (programmer mode)
	if _is_int(a) and _is_int(b):
		var x: int = a
		var y: int = b
		var r: Variant
		match op:
			BinOp.ADD:
				r = _checked_add(x, y)
			BinOp.SUB:
				r = _checked_sub(x, y)
			BinOp.MUL:
				r = _checked_mul(x, y)
			BinOp.DIV:
				if y == 0:
					return _fail(CalcError.DIV_BY_ZERO)
				r = null if (x == INT_MIN and y == -1) else x / y
			BinOp.MOD:
				if y == 0:
					return _fail(CalcError.DIV_BY_ZERO)
				r = null if (x == INT_MIN and y == -1) else x % y
			BinOp.POW:
				if y < 0 or y > 4294967295:
					return _fail(CalcError.OVERFLOW)
				r = _checked_pow(x, y)
			_: # YROOT
				var f := pow(float(x), 1.0 / float(y))
				if is_nan(f) or is_inf(f):
					return _fail(CalcError.DOMAIN)
				return _ok(_as_i64(f))
		if r == null:
			return _fail(CalcError.OVERFLOW)
		return _ok(r)
	# float path
	var fx := _as_f64(a)
	var fy := _as_f64(b)
	var fr: float
	match op:
		BinOp.ADD:
			fr = fx + fy
		BinOp.SUB:
			fr = fx - fy
		BinOp.MUL:
			fr = fx * fy
		BinOp.DIV:
			if fy == 0.0:
				return _fail(CalcError.DIV_BY_ZERO)
			fr = fx / fy
		BinOp.MOD:
			if fy == 0.0:
				return _fail(CalcError.DIV_BY_ZERO)
			var q := fx / fy
			fr = fx - fy * (floorf(q) if q >= 0.0 else ceilf(q))
		BinOp.POW:
			fr = pow(fx, fy)
		_: # YROOT
			fr = pow(fx, 1.0 / fy)
	if is_nan(fr):
		return _fail(CalcError.DOMAIN)
	if is_inf(fr):
		return _fail(CalcError.OVERFLOW)
	return _ok(fr)


## Rust wrapping_shl/shr: the shift amount is masked to 0..63 (`y as u32`
## keeps the low 32 bits, and the mask keeps the low 6).
static func _wrapping_shl(x: int, y: int) -> int:
	return x << (y & 63)


static func _wrapping_shr(x: int, y: int) -> int:
	return x >> (y & 63) # arithmetic, like i64 >>


## Evaluate a token slice with precedence climbing. Assumes balanced parens and
## no trailing operator. Returns [error, value].
static func eval_tokens(toks: Array) -> Array:
	var pos := [0]
	var r := _parse_expr(toks, pos, 0)
	if r[0] != CalcError.NONE:
		return r
	if pos[0] != toks.size():
		return _fail(CalcError.INVALID_EXPR)
	return r


static func _parse_expr(toks: Array, pos: Array, min_prec: int) -> Array:
	var lhs := _parse_atom(toks, pos)
	if lhs[0] != CalcError.NONE:
		return lhs
	while pos[0] < toks.size() and toks[pos[0]][0] == _T_OP:
		var op: BinOp = toks[pos[0]][1]
		var prec := binop_precedence(op)
		if prec < min_prec:
			break
		pos[0] += 1
		var next_min := prec if binop_right_assoc(op) else prec + 1
		var rhs := _parse_expr(toks, pos, next_min)
		if rhs[0] != CalcError.NONE:
			return rhs
		lhs = apply_binary(op, lhs[1], rhs[1])
		if lhs[0] != CalcError.NONE:
			return lhs
	return lhs


static func _parse_atom(toks: Array, pos: Array) -> Array:
	if pos[0] >= toks.size():
		return _fail(CalcError.INVALID_EXPR)
	var t: Array = toks[pos[0]]
	match t[0]:
		_T_VAL:
			pos[0] += 1
			return _ok(t[1])
		_T_LPAREN:
			pos[0] += 1
			var v := _parse_expr(toks, pos, 0)
			if v[0] != CalcError.NONE:
				return v
			if pos[0] < toks.size() and toks[pos[0]][0] == _T_RPAREN:
				pos[0] += 1
				return v
			return _fail(CalcError.INVALID_EXPR)
		_T_OP:
			if t[1] == BinOp.SUB:
				# unary minus: "- x"
				pos[0] += 1
				var a := _parse_atom(toks, pos)
				if a[0] != CalcError.NONE:
					return a
				if typeof(a[1]) == TYPE_FLOAT:
					return _ok(-float(a[1]))
				var n: int = a[1]
				return _ok(0 - n if n != INT_MIN else INT_MIN)
	return _fail(CalcError.INVALID_EXPR)
