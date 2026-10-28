extends GcTestCase
## Exact decimal <-> binary64 conversion against reference data: parse cases
## were produced with a correctly rounded parser (Python float()), format cases
## with the Rust implementation of fmt_f64 in Gosh Calc 0.2.


func _hex(v: int) -> String:
	return GcTestCodec.hex64(v)


func test_parse_matches_correctly_rounded_reference() -> void:
	var bad := 0
	var total := 0
	for line in GcCorpus.read_lines("res://tests/golden/parse_cases.tsv.gz"):
		var parts := line.split("\t")
		var v: Variant = GcNum.parse_f64(parts[0])
		total += 1
		var got := "null" if v == null else _hex(GcNum.bits_of(v))
		if got != parts[1]:
			bad += 1
			if bad <= 5:
				check(false, "parse %s: want %s got %s" % [parts[0], parts[1], got])
	check(total > 6000)
	eq(bad, 0)


func test_fmt_f64_matches_rust_reference() -> void:
	var bad := 0
	var total := 0
	for line in GcCorpus.read_lines("res://tests/golden/fmt_cases.tsv.gz"):
		var parts := line.split("\t")
		var bits := 0
		for ch in parts[0]:
			bits = (bits << 4) | "0123456789abcdef".find(ch)
		var got := GcNum.fmt_f64(GcNum.from_bits(bits))
		total += 1
		if got != parts[1]:
			bad += 1
			if bad <= 5:
				check(false, "fmt %s: want %s got %s" % [parts[0], parts[1], got])
	check(total > 8000)
	eq(bad, 0)


func test_parse_rejects_what_rust_rejects() -> void:
	for s in ["", "-", "+", ".", "e5", "1e", "1e+", "1e-", "1.5e-", "--1", "1..2", "1 ", " 1", "0x10", "1,5", "1_000", "٣"]:
		eq(GcNum.parse_f64(s), null, "accepted '%s'" % s)
	for pair in [["5.", 5.0], [".5", 0.5], ["+.5e1", 5.0], ["-0", -0.0], ["1E3", 1000.0], ["1e+3", 1000.0]]:
		eq(GcNum.parse_f64(pair[0]), pair[1], pair[0])
	check(is_inf(GcNum.parse_f64("1e999")))
	check(is_inf(GcNum.parse_f64("-inf")))
	check(is_inf(GcNum.parse_f64("Infinity")))
	check(is_nan(GcNum.parse_f64("NaN")))
	eq(GcNum.parse_f64("1e-999"), 0.0)
	eq(GcNum.bits_of(GcNum.parse_f64("-0.0")), GcNum.SIGN_BIT)


func test_round_half_to_even_on_exact_ties() -> void:
	eq(GcNum.fmt_f64(GcNum.parse_f64("1234567890125")), "1234567890120")
	eq(GcNum.fmt_f64(GcNum.parse_f64("1234567890135")), "1234567890140")
	eq(GcNum.fmt_f64(GcNum.parse_f64("123456789012.5")), "123456789012")
	eq(GcNum.fmt_f64(GcNum.parse_f64("123456789013.5")), "123456789014")
	eq(GcNum.fmt_f64(GcNum.parse_f64("999999999999.5")), "1000000000000")


func test_shortest_round_trip() -> void:
	for text in ["0.1", "0.2", "0.3", "1e22", "1e-7", "123456789.123456789", "5e-324", "1.7976931348623157e308"]:
		var v: float = GcNum.parse_f64(text)
		var s := GcNum.shortest_f64(v)
		eq(GcNum.bits_of(GcNum.parse_f64(s)), GcNum.bits_of(v), text + " -> " + s)
