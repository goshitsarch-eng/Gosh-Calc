class_name GcJson
extends RefCounted
## Strict JSON reader/writer for the settings file.
##
## Godot's built-in JSON turns every integer into a float, which would silently
## corrupt programmer-mode history above 2^53, so the settings file is read
## here. Behaviour follows serde_json: RFC 8259 only (no comments, trailing
## commas, leading zeros or BOM), integers stay exact `int`, and anything that
## does not fit i64 becomes a `float`.

const MAX_DEPTH := 128

var _s := ""
var _i := 0
var _n := 0
var error := ""


## Returns {"ok": bool, "value": Variant, "error": String}.
static func parse(text: String) -> Dictionary:
	var p := GcJson.new()
	p._s = text
	p._n = text.length()
	p._skip_ws()
	var v: Variant = p._value(0)
	if p.error.is_empty():
		p._skip_ws()
		if p._i != p._n:
			p.error = "trailing characters"
	if not p.error.is_empty():
		return {"ok": false, "value": null, "error": p.error}
	return {"ok": true, "value": v, "error": ""}


func _fail(msg: String) -> Variant:
	if error.is_empty():
		error = msg
	return null


func _skip_ws() -> void:
	while _i < _n:
		var c := _s.unicode_at(_i)
		if c == 32 or c == 9 or c == 10 or c == 13:
			_i += 1
		else:
			break


func _value(depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return _fail("recursion limit exceeded")
	if _i >= _n:
		return _fail("unexpected end")
	var c := _s[_i]
	match c:
		"{":
			return _object(depth)
		"[":
			return _array(depth)
		"\"":
			return _string()
		"t":
			return _literal("true", true)
		"f":
			return _literal("false", false)
		"n":
			return _literal("null", null)
	if c == "-" or (c >= "0" and c <= "9"):
		return _number()
	return _fail("unexpected character")


func _literal(word: String, value: Variant) -> Variant:
	if _s.substr(_i, word.length()) != word:
		return _fail("invalid literal")
	_i += word.length()
	return value


func _object(depth: int) -> Variant:
	var out := {}
	_i += 1
	_skip_ws()
	if _i < _n and _s[_i] == "}":
		_i += 1
		return out
	while true:
		_skip_ws()
		if _i >= _n or _s[_i] != "\"":
			return _fail("expected string key")
		var key: Variant = _string()
		if not error.is_empty():
			return null
		_skip_ws()
		if _i >= _n or _s[_i] != ":":
			return _fail("expected colon")
		_i += 1
		_skip_ws()
		var v: Variant = _value(depth + 1)
		if not error.is_empty():
			return null
		out[key] = v
		_skip_ws()
		if _i >= _n:
			return _fail("unexpected end")
		if _s[_i] == ",":
			_i += 1
			continue
		if _s[_i] == "}":
			_i += 1
			return out
		return _fail("expected comma or brace")
	return null


func _array(depth: int) -> Variant:
	var out := []
	_i += 1
	_skip_ws()
	if _i < _n and _s[_i] == "]":
		_i += 1
		return out
	while true:
		_skip_ws()
		var v: Variant = _value(depth + 1)
		if not error.is_empty():
			return null
		out.append(v)
		_skip_ws()
		if _i >= _n:
			return _fail("unexpected end")
		if _s[_i] == ",":
			_i += 1
			continue
		if _s[_i] == "]":
			_i += 1
			return out
		return _fail("expected comma or bracket")
	return null


func _hex4() -> int:
	if _i + 4 > _n:
		_fail("bad escape")
		return -1
	var v := 0
	for k in 4:
		var c := _s.unicode_at(_i + k)
		var d: int
		if c >= 48 and c <= 57:
			d = c - 48
		elif c >= 65 and c <= 70:
			d = c - 55
		elif c >= 97 and c <= 102:
			d = c - 87
		else:
			_fail("bad escape")
			return -1
		v = v * 16 + d
	_i += 4
	return v


func _string() -> Variant:
	_i += 1 # opening quote
	var out := PackedStringArray()
	var run_start := _i
	while true:
		if _i >= _n:
			return _fail("unterminated string")
		var c := _s.unicode_at(_i)
		if c == 34:
			out.append(_s.substr(run_start, _i - run_start))
			_i += 1
			return "".join(out)
		if c < 32:
			return _fail("control character in string")
		if c != 92:
			_i += 1
			continue
		out.append(_s.substr(run_start, _i - run_start))
		_i += 1
		if _i >= _n:
			return _fail("unterminated string")
		var e := _s[_i]
		_i += 1
		match e:
			"\"": out.append("\"")
			"\\": out.append("\\")
			"/": out.append("/")
			"b": out.append(char(8))
			"f": out.append(char(12))
			"n": out.append("\n")
			"r": out.append("\r")
			"t": out.append("\t")
			"u":
				var cp := _hex4()
				if cp < 0:
					return null
				if cp >= 0xD800 and cp <= 0xDBFF:
					if _i + 2 <= _n and _s[_i] == "\\" and _s[_i + 1] == "u":
						_i += 2
						var lo := _hex4()
						if lo < 0:
							return null
						if lo < 0xDC00 or lo > 0xDFFF:
							return _fail("lone surrogate")
						cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
					else:
						return _fail("lone surrogate")
				elif cp >= 0xDC00 and cp <= 0xDFFF:
					return _fail("lone surrogate")
				out.append(char(cp))
			_:
				return _fail("invalid escape")
		run_start = _i
	return null


func _number() -> Variant:
	var start := _i
	if _s[_i] == "-":
		_i += 1
	if _i >= _n:
		return _fail("invalid number")
	if _s[_i] == "0":
		_i += 1
	elif _s[_i] >= "1" and _s[_i] <= "9":
		while _i < _n and GcNum.is_ascii_digit(_s[_i]):
			_i += 1
	else:
		return _fail("invalid number")
	var is_float := false
	if _i < _n and _s[_i] == ".":
		is_float = true
		_i += 1
		var f0 := _i
		while _i < _n and GcNum.is_ascii_digit(_s[_i]):
			_i += 1
		if _i == f0:
			return _fail("invalid number")
	if _i < _n and (_s[_i] == "e" or _s[_i] == "E"):
		is_float = true
		_i += 1
		if _i < _n and (_s[_i] == "+" or _s[_i] == "-"):
			_i += 1
		var e0 := _i
		while _i < _n and GcNum.is_ascii_digit(_s[_i]):
			_i += 1
		if _i == e0:
			return _fail("invalid number")
	var text := _s.substr(start, _i - start)
	if not is_float:
		var iv: Variant = GcEngine._parse_i64(text)
		if iv != null:
			return iv
	var fv: Variant = GcNum.parse_f64(text)
	if fv == null:
		return _fail("invalid number")
	return fv


# ---------- writing ----------

## Pretty-prints like serde_json::to_vec_pretty (two-space indent). Floats are
## written as the shortest decimal that parses back exactly; ints stay ints.
static func stringify(value: Variant, indent: int = 0) -> String:
	var pad := "  ".repeat(indent + 1)
	var end_pad := "  ".repeat(indent)
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return GcNum.shortest_f64(value)
		TYPE_STRING:
			return _quote(value)
		TYPE_ARRAY:
			if value.is_empty():
				return "[]"
			var items := PackedStringArray()
			for v in value:
				items.append(pad + stringify(v, indent + 1))
			return "[\n" + ",\n".join(items) + "\n" + end_pad + "]"
		TYPE_DICTIONARY:
			if value.is_empty():
				return "{}"
			var items := PackedStringArray()
			for k in value:
				items.append(pad + _quote(str(k)) + ": " + stringify(value[k], indent + 1))
			return "{\n" + ",\n".join(items) + "\n" + end_pad + "}"
	return "null"


static func _quote(s: String) -> String:
	var out := PackedStringArray(["\""])
	var run_start := 0
	for i in s.length():
		var c := s.unicode_at(i)
		var esc := ""
		match c:
			34: esc = "\\\""
			92: esc = "\\\\"
			8: esc = "\\b"
			12: esc = "\\f"
			10: esc = "\\n"
			13: esc = "\\r"
			9: esc = "\\t"
			_:
				if c < 32:
					esc = "\\u%04x" % c
		if not esc.is_empty():
			out.append(s.substr(run_start, i - run_start))
			out.append(esc)
			run_start = i + 1
	out.append(s.substr(run_start))
	out.append("\"")
	return "".join(out)
