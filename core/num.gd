class_name GcNum
extends RefCounted
## Exact decimal <-> binary64 conversion.
##
## Godot's String.to_float() and printf-style formatting are not correctly
## rounded, which would silently change the last displayed digit compared with
## earlier versions of Gosh Calc. Everything here is exact: parsing matches
## IEEE round-half-even and formatting rounds the *exact* binary value half to
## even, the same as `f64::from_str` and `format!("{:.11e}")` in the Rust
## releases.

const SIGN_BIT := 1 << 63 # INT64_MIN: only the sign bit set
const EXP_MASK := 0x7FF
const FRAC_MASK := (1 << 52) - 1
const POS_INF_BITS := 0x7FF0000000000000
const MAX_FINITE_BITS := 0x7FEFFFFFFFFFFFFF
## Doubles are fully determined by 767 significant digits.
const MAX_PARSE_DIGITS := 800


static func bits_of(v: float) -> int:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.decode_s64(0)


static func from_bits(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, bits)
	return b.decode_double(0)


static func is_ascii_digit(c: String) -> bool:
	return c.length() == 1 and c.unicode_at(0) >= 48 and c.unicode_at(0) <= 57


## Rust `f64::from_str` grammar. Returns null for anything Rust rejects.
static func parse_f64(s: String) -> Variant:
	var n := s.length()
	var i := 0
	var neg := false
	if i < n and (s[i] == "+" or s[i] == "-"):
		neg = s[i] == "-"
		i += 1
	var word := s.substr(i).to_lower()
	if word == "inf" or word == "infinity":
		return -INF if neg else INF
	if word == "nan":
		return NAN
	var int_start := i
	while i < n and is_ascii_digit(s[i]):
		i += 1
	var int_digits := s.substr(int_start, i - int_start)
	var frac_digits := ""
	if i < n and s[i] == ".":
		i += 1
		var frac_start := i
		while i < n and is_ascii_digit(s[i]):
			i += 1
		frac_digits = s.substr(frac_start, i - frac_start)
	if int_digits.is_empty() and frac_digits.is_empty():
		return null
	var exp_val := 0
	if i < n and (s[i] == "e" or s[i] == "E"):
		i += 1
		var exp_neg := false
		if i < n and (s[i] == "+" or s[i] == "-"):
			exp_neg = s[i] == "-"
			i += 1
		var exp_start := i
		while i < n and is_ascii_digit(s[i]):
			if exp_val < 100000000:
				exp_val = exp_val * 10 + s.unicode_at(i) - 48
			i += 1
		if i == exp_start:
			return null
		if exp_neg:
			exp_val = -exp_val
	if i != n:
		return null
	return _decimal_to_f64(neg, int_digits + frac_digits, exp_val - frac_digits.length())


static func _signed_zero(neg: bool) -> float:
	return from_bits(SIGN_BIT) if neg else 0.0


## value = digits * 10^k, correctly rounded.
static func _decimal_to_f64(neg: bool, digits: String, k: int) -> float:
	var start := 0
	while start < digits.length() and digits[start] == "0":
		start += 1
	digits = digits.substr(start)
	if digits.is_empty():
		return _signed_zero(neg)
	var stop := digits.length()
	while stop > 1 and digits[stop - 1] == "0":
		stop -= 1
	k += digits.length() - stop
	digits = digits.substr(0, stop)
	if digits.length() > MAX_PARSE_DIGITS:
		# Keep a sticky nonzero digit so ties are still seen as above-half.
		digits = digits.substr(0, MAX_PARSE_DIGITS - 1) + "1"
		k += stop - MAX_PARSE_DIGITS
	var sci := k + digits.length() - 1
	if sci >= 309:
		return -INF if neg else INF
	if sci < -325:
		return _signed_zero(neg)
	var mag: float
	if digits.length() <= 15 and absi(k) <= 22:
		# Clinger fast path: both operands are exact doubles, one rounding.
		var d := float(digits.to_int())
		mag = d * _pow10(k) if k >= 0 else d / _pow10(-k)
	else:
		mag = _decimal_to_f64_exact(digits, k, sci)
	return -mag if neg else mag


static var _pow10_table := PackedFloat64Array()


## 10^n is exactly representable as a double for 0 <= n <= 22.
static func _pow10(n: int) -> float:
	if _pow10_table.is_empty():
		var p := 1.0
		for _i in 23:
			_pow10_table.append(p)
			p *= 10.0
	return _pow10_table[n]


## Seed for the exact walk: within a handful of ulps of digits * 10^k, built
## only from operations that are exact or round once (never String.to_float,
## which flushes ordinary small values such as 1.3e-292 to zero).
static func _estimate(digits: String, sci: int) -> float:
	var lead := mini(digits.length(), 15)
	var mag := float(digits.substr(0, lead).to_int()) / _pow10(lead - 1)
	var e := sci
	while e > 22:
		mag *= _pow10(22)
		e -= 22
	while e < -22:
		mag /= _pow10(22)
		e += 22
	return mag * _pow10(e) if e >= 0 else mag / _pow10(-e)


static func _decimal_to_f64_exact(digits: String, k: int, sci: int) -> float:
	# Start from the engine's approximation, then walk to the correctly
	# rounded neighbour using exact comparisons against the rounding midpoints.
	var approx := _estimate(digits, sci)
	var bits := bits_of(approx)
	if bits < 0 or bits >= POS_INF_BITS:
		bits = MAX_FINITE_BITS if sci >= 308 else 0
	for _step in 4096:
		var exp_bits := (bits >> 52) & EXP_MASK
		var frac := bits & FRAC_MASK
		var m: int
		var e: int
		if exp_bits == 0:
			m = frac
			e = -1074
		else:
			m = frac | (1 << 52)
			e = exp_bits - 1075
		var odd := (m & 1) == 1
		var up := _cmp_decimal_binary(digits, k, 2 * m + 1, e - 1)
		if up > 0 or (up == 0 and odd):
			bits += 1
			if bits >= POS_INF_BITS:
				return INF
			continue
		if bits > 0:
			var low: int
			if m == (1 << 52) and exp_bits > 1:
				low = _cmp_decimal_binary(digits, k, 4 * m - 1, e - 2)
			else:
				low = _cmp_decimal_binary(digits, k, 2 * m - 1, e - 1)
			if low < 0 or (low == 0 and odd):
				bits -= 1
				continue
		break
	return from_bits(bits)


## Compares digits * 10^k with m * 2^e exactly: -1, 0 or 1.
static func _cmp_decimal_binary(digits: String, k: int, m: int, e: int) -> int:
	var lhs := GcBig.from_digits(digits)
	var rhs := GcBig.from_int(m)
	if k > 0:
		lhs.mul_pow5(k)
	elif k < 0:
		rhs.mul_pow5(-k)
	var twos := k - e
	if twos > 0:
		lhs.mul_pow2(twos)
	elif twos < 0:
		rhs.mul_pow2(-twos)
	return lhs.compare(rhs)


## Exact decimal expansion of a positive finite double: [digits, exp10] where
## the value is 0.d1d2... shifted so that d1 is the 10^exp10 digit.
static func exact_digits(x: float) -> Array:
	var bits := bits_of(x) & ~SIGN_BIT
	var exp_bits := (bits >> 52) & EXP_MASK
	var frac := bits & FRAC_MASK
	var m: int
	var e: int
	if exp_bits == 0:
		m = frac
		e = -1074
	else:
		m = frac | (1 << 52)
		e = exp_bits - 1075
	var big := GcBig.from_int(m)
	if e >= 0:
		big.mul_pow2(e)
	else:
		big.mul_pow5(-e)
	var s := big.to_decimal()
	return [s, s.length() - 1 + mini(e, 0)]


## `n` significant digits of |x| (x finite, nonzero), exact value rounded half
## to even. Returns [digit string of length n, decimal exponent of first digit].
static func sig_digits(x: float, n: int) -> Array:
	var exact := exact_digits(absf(x))
	var s: String = exact[0]
	var exp10: int = int(exact[1])
	if s.length() <= n:
		return [s + "0".repeat(n - s.length()), exp10]
	var head := s.substr(0, n)
	var next_digit := s.unicode_at(n) - 48
	var up := false
	if next_digit > 5:
		up = true
	elif next_digit == 5:
		var sticky := false
		for i in range(n + 1, s.length()):
			if s[i] != "0":
				sticky = true
				break
		if sticky:
			up = true
		else:
			up = (head.unicode_at(n - 1) - 48) % 2 == 1
	if up:
		var chars := head.to_utf8_buffer()
		var i := n - 1
		while i >= 0:
			if chars[i] == 57:
				chars[i] = 48
				i -= 1
			else:
				chars[i] += 1
				break
		if i < 0:
			# 99..9 rounded up to 100..0
			return ["1" + "0".repeat(n - 1), exp10 + 1]
		head = chars.get_string_from_ascii()
	return [head, exp10]


## Display format: up to 12 significant digits, trailing zeros trimmed, and
## exponent notation outside 1e-9 <= |v| < 1e16. Identical to the Rust fmt_f64.
static func fmt_f64(v: float) -> String:
	if v == 0.0:
		return "0"
	if is_nan(v) or is_inf(v):
		return "Error"
	var sd := sig_digits(v, 12)
	var d: String = sd[0]
	var exp := int(sd[1])
	var mant := d.substr(0, 1) + "." + d.substr(1)
	mant = _trim_end(mant, "0")
	mant = _trim_end(mant, ".")
	if v < 0.0:
		mant = "-" + mant
	if exp < -9 or exp >= 16:
		return "%se%d" % [mant, exp]
	var neg := mant.begins_with("-")
	var digits := ""
	for c in mant:
		if is_ascii_digit(c):
			digits += c
	var ndig := digits.length()
	var out := "-" if neg else ""
	if exp >= 0:
		var int_len := exp + 1
		if ndig <= int_len:
			out += digits + "0".repeat(int_len - ndig)
		else:
			out += digits.substr(0, int_len)
			var frac := _trim_end(digits.substr(int_len), "0")
			if not frac.is_empty():
				out += "." + frac
	else:
		out += "0." + "0".repeat(-exp - 1) + digits
	return out


## Shortest decimal string that parses back to exactly `v` (JSON output).
static func shortest_f64(v: float) -> String:
	if v == 0.0:
		return "-0.0" if bits_of(v) < 0 else "0.0"
	for p in range(1, 18):
		var sd := sig_digits(v, p)
		var d: String = sd[0]
		var exp := int(sd[1])
		var text := d.substr(0, 1) + ("." + d.substr(1) if p > 1 else "") + "e" + str(exp)
		var back = parse_f64(text)
		if back != null and bits_of(back) == bits_of(absf(v)):
			return _plain_or_scientific(v < 0.0, _trim_end(d, "0"), exp)
	return str(v)


static func _plain_or_scientific(neg: bool, d: String, exp: int) -> String:
	if d.is_empty():
		d = "0"
	var sign := "-" if neg else ""
	if exp < -5 or exp >= 16:
		# serde_json style: "1e+21", "1.5e-7"
		return sign + d.substr(0, 1) + ("." + d.substr(1) if d.length() > 1 else "") \
				+ ("e+" if exp > 0 else "e") + str(exp)
	if exp >= 0:
		var int_len := exp + 1
		if d.length() <= int_len:
			return sign + d + "0".repeat(int_len - d.length()) + ".0"
		return sign + d.substr(0, int_len) + "." + d.substr(int_len)
	return sign + "0." + "0".repeat(-exp - 1) + d


static func _trim_end(s: String, ch: String) -> String:
	var end := s.length()
	while end > 0 and s[end - 1] == ch:
		end -= 1
	return s.substr(0, end)
