class_name GcBig
extends RefCounted
## Minimal non-negative big integer (little-endian limbs, base 1e9).
##
## Only what exact decimal <-> binary64 conversion needs: multiply by small
## numbers, powers of two and five, compare, and print. Not a general bignum.

const BASE := 1000000000
const POW5_13 := 1220703125 # 5^13, largest power of five below 2^31
const POW2_30 := 1073741824

var limbs := PackedInt64Array([0])


static func from_int(n: int) -> GcBig:
	var b := GcBig.new()
	b.limbs = PackedInt64Array()
	if n <= 0:
		b.limbs.append(0)
		return b
	while n > 0:
		b.limbs.append(n % BASE)
		n /= BASE
	return b


## `digits` must be ASCII decimal digits only.
static func from_digits(digits: String) -> GcBig:
	var b := GcBig.new()
	b.limbs = PackedInt64Array()
	var end := digits.length()
	while end > 0:
		var start := maxi(0, end - 9)
		b.limbs.append(digits.substr(start, end - start).to_int())
		end = start
	if b.limbs.is_empty():
		b.limbs.append(0)
	b._trim()
	return b


func _trim() -> void:
	while limbs.size() > 1 and limbs[limbs.size() - 1] == 0:
		limbs.remove_at(limbs.size() - 1)


func is_zero() -> bool:
	return limbs.size() == 1 and limbs[0] == 0


## `n` must be in 0 ..< 2^31 so limb * n + carry stays inside int64.
func mul_small(n: int) -> void:
	if n == 0:
		limbs = PackedInt64Array([0])
		return
	var carry := 0
	for i in limbs.size():
		var cur := limbs[i] * n + carry
		limbs[i] = cur % BASE
		carry = cur / BASE
	while carry > 0:
		limbs.append(carry % BASE)
		carry /= BASE


func mul_pow2(k: int) -> void:
	while k >= 30:
		mul_small(POW2_30)
		k -= 30
	if k > 0:
		mul_small(1 << k)


func mul_pow5(k: int) -> void:
	while k >= 13:
		mul_small(POW5_13)
		k -= 13
	var p := 1
	for _i in k:
		p *= 5
	if p > 1:
		mul_small(p)


func compare(other: GcBig) -> int:
	if limbs.size() != other.limbs.size():
		return -1 if limbs.size() < other.limbs.size() else 1
	var i := limbs.size() - 1
	while i >= 0:
		if limbs[i] != other.limbs[i]:
			return -1 if limbs[i] < other.limbs[i] else 1
		i -= 1
	return 0


func to_decimal() -> String:
	var s := str(limbs[limbs.size() - 1])
	var i := limbs.size() - 2
	while i >= 0:
		s += "%09d" % limbs[i]
		i -= 1
	return s
