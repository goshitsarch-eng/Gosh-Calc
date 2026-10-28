class_name GcRon
extends RefCounted
## Reader for the small subset of RON that the legacy libcosmic/cosmic-config
## release wrote: strings, numbers, booleans, lists, structs (named or not) and
## enum variants such as `Some(F(1.5))`.
##
## Values map to: String, int, float, bool, Array, Dictionary (structs), and
## {"$variant": name, "$value": payload-or-null} for enum variants and `None`.
## Anything outside the subset is rejected rather than guessed at, so a
## malformed legacy file leaves the user's original data untouched.

const MAX_DEPTH := 64

var _s := ""
var _i := 0
var _n := 0
var error := ""


## Returns {"ok": bool, "value": Variant}.
static func parse(text: String) -> Dictionary:
	var p := GcRon.new()
	p._s = text
	p._n = text.length()
	p._ws()
	var v: Variant = p._value(0)
	if p.error.is_empty():
		p._ws()
		if p._i != p._n:
			p.error = "trailing characters"
	return {"ok": p.error.is_empty(), "value": v}


func _fail(msg: String) -> Variant:
	if error.is_empty():
		error = msg
	return null


func _ws() -> void:
	while _i < _n:
		var c := _s.unicode_at(_i)
		if c == 32 or c == 9 or c == 10 or c == 13:
			_i += 1
		elif c == 47 and _i + 1 < _n and _s[_i + 1] == "/":
			while _i < _n and _s[_i] != "\n":
				_i += 1
		elif c == 47 and _i + 1 < _n and _s[_i + 1] == "*":
			var close := _s.find("*/", _i + 2)
			if close < 0:
				_fail("unterminated comment")
				_i = _n
				return
			_i = close + 2
		else:
			break


static func _is_ident_start(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95


static func _is_ident(c: int) -> bool:
	return _is_ident_start(c) or (c >= 48 and c <= 57)


func _value(depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return _fail("too deeply nested")
	if _i >= _n:
		return _fail("unexpected end")
	var c := _s.unicode_at(_i)
	if c == 34:
		return _string()
	if c == 114 and _i + 1 < _n and (_s[_i + 1] == "\"" or _s[_i + 1] == "#"):
		return _raw_string()
	if c == 91:
		return _list(depth)
	if c == 40:
		var body: Variant = _struct_body(depth)
		return null if body == null else body[1]
	if c == 45 or c == 43 or (c >= 48 and c <= 57):
		return _number()
	if _is_ident_start(c):
		var start := _i
		while _i < _n and _is_ident(_s.unicode_at(_i)):
			_i += 1
		var word := _s.substr(start, _i - start)
		_ws()
		if _i < _n and _s[_i] == "(":
			var body: Variant = _struct_body(depth)
			if not error.is_empty():
				return null
			# `Name(field: ..)` is a struct; `Variant(x)` carries a payload
			if body[0]:
				return body[1]
			return {"$variant": word, "$value": body[1]}
		if word == "true":
			return true
		if word == "false":
			return false
		return {"$variant": word, "$value": null}
	return _fail("unexpected character")


func _list(depth: int) -> Variant:
	var out := []
	_i += 1
	while true:
		_ws()
		if _i >= _n:
			return _fail("unexpected end")
		if _s[_i] == "]":
			_i += 1
			return out
		out.append(_value(depth + 1))
		if not error.is_empty():
			return null
		_ws()
		if _i < _n and _s[_i] == ",":
			_i += 1
		elif _i < _n and _s[_i] != "]":
			return _fail("expected comma")
	return null


## `( ... )`. Returns [named, value]: a struct body `field: value, ...` yields
## [true, Dictionary]; a single unnamed value (enum payload / newtype) yields
## [false, that value]; several unnamed values yield [false, Array] (tuple).
func _struct_body(depth: int) -> Variant:
	_i += 1
	var fields := {}
	var items := []
	var named := false
	while true:
		_ws()
		if _i >= _n:
			return _fail("unexpected end")
		if _s[_i] == ")":
			_i += 1
			break
		# field name?
		var saved := _i
		var name := ""
		if _is_ident_start(_s.unicode_at(_i)):
			var start := _i
			while _i < _n and _is_ident(_s.unicode_at(_i)):
				_i += 1
			name = _s.substr(start, _i - start)
			_ws()
			if _i < _n and _s[_i] == ":":
				_i += 1
				_ws()
			else:
				_i = saved
				name = ""
		if not name.is_empty():
			named = true
			fields[name] = _value(depth + 1)
		else:
			items.append(_value(depth + 1))
		if not error.is_empty():
			return null
		_ws()
		if _i < _n and _s[_i] == ",":
			_i += 1
		elif _i < _n and _s[_i] != ")":
			return _fail("expected comma")
	if named:
		if not items.is_empty():
			return _fail("mixed fields")
		return [true, fields]
	if items.size() == 1:
		return [false, items[0]]
	return [false, items]


func _number() -> Variant:
	var start := _i
	if _s[_i] == "-" or _s[_i] == "+":
		_i += 1
	var is_float := false
	while _i < _n:
		var c := _s[_i]
		if GcNum.is_ascii_digit(c) or c == "_":
			_i += 1
		elif c == "." or c == "e" or c == "E":
			is_float = true
			_i += 1
			if (c == "e" or c == "E") and _i < _n and (_s[_i] == "+" or _s[_i] == "-"):
				_i += 1
		else:
			break
	var text := _s.substr(start, _i - start).replace("_", "")
	if text.begins_with("+"):
		text = text.substr(1)
	if not is_float:
		var iv: Variant = GcEngine._parse_i64(text)
		if iv != null:
			return iv
	var fv: Variant = GcNum.parse_f64(text)
	if fv == null:
		return _fail("invalid number")
	return fv


func _string() -> Variant:
	_i += 1
	var out := PackedStringArray()
	while true:
		if _i >= _n:
			return _fail("unterminated string")
		var c := _s[_i]
		_i += 1
		if c == "\"":
			return "".join(out)
		if c != "\\":
			out.append(c)
			continue
		if _i >= _n:
			return _fail("unterminated string")
		var e := _s[_i]
		_i += 1
		match e:
			"\"": out.append("\"")
			"\\": out.append("\\")
			"'": out.append("'")
			"n": out.append("\n")
			"r": out.append("\r")
			"t": out.append("\t")
			"b": out.append(char(8))
			"f": out.append(char(12))
			"0": return _fail("NUL characters are not supported")
			"x":
				var hv := _hex(2)
				if hv < 0:
					return null
				out.append(char(hv))
			"u":
				var cp := -1
				if _i < _n and _s[_i] == "{":
					var close := _s.find("}", _i)
					if close < 0:
						return _fail("bad unicode escape")
					var digits := _s.substr(_i + 1, close - _i - 1)
					if digits.is_empty() or not _all_hex(digits):
						return _fail("bad unicode escape")
					cp = digits.hex_to_int()
					_i = close + 1
				else:
					cp = _hex(4)
				if cp < 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
					return _fail("bad unicode escape")
				out.append(char(cp))
			_:
				return _fail("invalid escape")
	return null


func _hex(count: int) -> int:
	if _i + count > _n:
		_fail("bad escape")
		return -1
	var digits := _s.substr(_i, count)
	if not _all_hex(digits):
		_fail("bad escape")
		return -1
	_i += count
	return digits.hex_to_int()


static func _all_hex(s: String) -> bool:
	for k in s.length():
		var c := s.unicode_at(k)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102)):
			return false
	return true


func _raw_string() -> Variant:
	_i += 1 # r
	var hashes := 0
	while _i < _n and _s[_i] == "#":
		hashes += 1
		_i += 1
	if _i >= _n or _s[_i] != "\"":
		return _fail("bad raw string")
	_i += 1
	var terminator := "\"" + "#".repeat(hashes)
	var close := _s.find(terminator, _i)
	if close < 0:
		return _fail("unterminated raw string")
	var text := _s.substr(_i, close - _i)
	_i = close + terminator.length()
	return text
