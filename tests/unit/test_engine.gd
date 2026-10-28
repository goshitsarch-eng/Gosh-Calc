extends GcTestCase
## Port of the engine unit tests from Gosh Calc 0.2 (src/engine.rs).

const E := preload("res://core/engine.gd")
const BinOp := E.BinOp
const UnaryOp := E.UnaryOp
const Mode := E.Mode
const Base := E.Base
const Err := E.CalcError


func _st() -> GcEngine:
	return GcEngine.new()


func _seq(s: GcEngine, keys: String) -> void:
	for ch in keys:
		match ch:
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
				s.input_digit(ch.unicode_at(0) - 48)
			"a", "b", "c", "d", "e", "f":
				s.input_digit(ch.unicode_at(0) - 97 + 10)
			".": s.input_dot()
			"+": s.input_binary(BinOp.ADD)
			"-": s.input_binary(BinOp.SUB)
			"*": s.input_binary(BinOp.MUL)
			"/": s.input_binary(BinOp.DIV)
			"^": s.input_binary(BinOp.POW)
			"(": s.input_lparen()
			")": s.input_rparen()
			"%": s.input_percent()
			"=": s.equals()
			"B": s.backspace()
			"n": s.toggle_sign()
			_: push_error("bad test key " + ch)


func _eval(keys: String) -> String:
	var s := _st()
	_seq(s, keys)
	return s.result_display()


func _f(text: String) -> float:
	return GcNum.parse_f64(text)


func test_basic_arithmetic() -> void:
	eq(_eval("2+3="), "5")
	eq(_eval("7-10="), "-3")
	eq(_eval("6*7="), "42")
	eq(_eval("20/8="), "2.5")


func test_precedence() -> void:
	eq(_eval("2+3*4="), "14")
	eq(_eval("2*3+4="), "10")
	eq(_eval("10-2*3="), "4")
	eq(_eval("2^3^2="), "512") # right-assoc


func test_float_artifacts_hidden() -> void:
	eq(_eval("0.1+0.2="), "0.3")
	eq(_eval("1.1*3="), "3.3")
	eq(_eval("2.3-2.2="), "0.1")


func test_chained_and_repeat() -> void:
	var s := _st()
	_seq(s, "2+3=")
	eq(s.result_display(), "5")
	s.equals()
	eq(s.result_display(), "8")
	s.equals()
	eq(s.result_display(), "11")


func test_continue_after_equals() -> void:
	var s := _st()
	_seq(s, "2+3=*2=")
	eq(s.result_display(), "10")


func test_op_correction() -> void:
	var s := _st()
	_seq(s, "2+*3=")
	eq(s.result_display(), "6")


func test_percent_semantics() -> void:
	eq(_eval("100+10%="), "110")
	eq(_eval("100-10%="), "90")
	eq(_eval("200*10%="), "20")
	eq(_eval("50%="), "0.5")


func test_unary_minus() -> void:
	eq(_eval("n5+8="), "3") # -5 + 8
	eq(_eval("2*n3="), "-6") # 2 * -3


func test_backspace_and_clear() -> void:
	var s := _st()
	_seq(s, "123B")
	eq(s.result_display(), "12")
	s.clear_entry()
	eq(s.result_display(), "0")
	_seq(s, "5+")
	s.clear_all()
	eq(s.result_display(), "0")
	eq(s.expression_display(), "")


func test_div_by_zero() -> void:
	var s := _st()
	_seq(s, "5/0=")
	eq(s.result_display(), "Error")
	eq(s.error, Err.DIV_BY_ZERO)
	s.input_digit(7) # recover with a digit
	eq(s.error, Err.NONE)
	eq(s.result_display(), "7")


func test_scientific_functions() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	_seq(s, "9")
	s.input_unary(UnaryOp.SQRT)
	eq(s.result_display(), "3")
	_seq(s, "B") # clears "3" -> empty
	s.clear_all()
	_seq(s, "2")
	s.input_unary(UnaryOp.CUBE)
	eq(s.result_display(), "8")
	s.clear_all()
	s.input_unary(UnaryOp.FACT) # 0! = 1
	eq(s.result_display(), "1")
	s.clear_all()
	_seq(s, "5")
	s.input_unary(UnaryOp.FACT)
	eq(s.result_display(), "120")
	s.clear_all()
	_seq(s, "10")
	s.input_unary(UnaryOp.LOG10)
	eq(s.result_display(), "1")
	s.clear_all()
	_seq(s, "1")
	s.input_unary(UnaryOp.LN)
	eq(s.result_display(), "0")


func test_trig_degrees_radians() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	_seq(s, "30")
	s.input_unary(UnaryOp.SIN)
	eq(s.result_display(), "0.5")
	s.toggle_angle() # Rad
	s.clear_all()
	s.input_const(E.Const.PI)
	s.input_unary(UnaryOp.SIN)
	eq(s.result_display(), "0")
	s.toggle_angle() # back to Deg
	s.clear_all()
	_seq(s, "1")
	s.input_unary(UnaryOp.ASIN)
	eq(s.result_display(), "90")


func test_parens() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	_seq(s, "(2+3)*4=")
	eq(s.result_display(), "20")
	s.clear_all()
	_seq(s, "(2+3=") # unclosed paren auto-closes
	eq(s.result_display(), "5")


func test_constants_and_overflow() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	s.input_const(E.Const.PI)
	eq(s.result_display(), "3.14159265359")
	s.clear_all()
	_seq(s, "n1")
	s.input_unary(UnaryOp.SQRT)
	eq(s.error, Err.DOMAIN)


func test_factorial_domain() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	_seq(s, "2.5")
	s.input_unary(UnaryOp.FACT)
	eq(s.error, Err.DOMAIN)
	s.clear_all()
	_seq(s, "171")
	s.input_unary(UnaryOp.FACT)
	eq(s.error, Err.OVERFLOW)


func test_programmer_bases() -> void:
	var s := _st()
	s.set_mode(Mode.PROGRAMMER)
	s.set_base(Base.HEX)
	_seq(s, "ff")
	eq(s.result_display(), "FF")
	s.set_base(Base.DEC)
	eq(s.result_display(), "255")
	s.set_base(Base.BIN)
	eq(s.result_display(), "11111111")
	s.set_base(Base.OCT)
	eq(s.result_display(), "377")


func test_programmer_bitwise() -> void:
	var s := _st()
	s.set_mode(Mode.PROGRAMMER)
	s.set_base(Base.HEX)
	_seq(s, "f0")
	s.input_binary(BinOp.AND)
	_seq(s, "0f")
	s.equals()
	eq(s.result_display(), "0")
	s.clear_all()
	_seq(s, "f0")
	s.input_binary(BinOp.OR)
	_seq(s, "0f")
	s.equals()
	eq(s.result_display(), "FF")
	s.input_unary(UnaryOp.NOT)
	eq(s.result_display(), "FFFFFFFFFFFFFF00")
	# shifts
	s.clear_all()
	s.set_base(Base.DEC)
	_seq(s, "1")
	s.input_binary(BinOp.SHL)
	_seq(s, "8")
	s.equals()
	eq(s.result_display(), "256")
	# modulo
	s.clear_all()
	_seq(s, "17")
	s.input_binary(BinOp.MOD)
	_seq(s, "5")
	s.equals()
	eq(s.result_display(), "2")


func test_programmer_int_division() -> void:
	var s := _st()
	s.set_mode(Mode.PROGRAMMER)
	_seq(s, "7/2=")
	eq(s.result_display(), "3")


func test_base_readout() -> void:
	var s := _st()
	s.set_mode(Mode.PROGRAMMER)
	_seq(s, "255")
	eq(s.base_readout(), ["FF", "255", "377", "11111111"])


func test_history_records() -> void:
	var s := _st()
	_seq(s, "2+3=")
	_seq(s, "10*2=")
	eq(s.history.size(), 2)
	eq(s.history[0]["expr"], "10 × 2")
	eq(s.history[0]["result"], "20")
	eq(s.history[1]["expr"], "2 + 3")
	s.recall_history(1)
	eq(s.result_display(), "5")
	s.clear_history()
	check(s.history.is_empty())


func test_mode_switch_converts() -> void:
	var s := _st()
	_seq(s, "42.9")
	s.set_mode(Mode.PROGRAMMER)
	eq(s.result_display(), "42")
	s.set_mode(Mode.STANDARD)
	eq(s.result_display(), "42")


func test_digit_filtered_by_base() -> void:
	var s := _st()
	s.set_mode(Mode.PROGRAMMER)
	s.set_base(Base.BIN)
	s.input_digit(1)
	s.input_digit(5) # ignored
	s.input_digit(0)
	eq(s.result_display(), "10")


func test_scientific_notation_display() -> void:
	eq(GcNum.fmt_f64(_f("1e16")), "1e16")
	eq(GcNum.fmt_f64(_f("1.5e-11")), "1.5e-11")
	eq(GcNum.fmt_f64(_f("1e15")), "1000000000000000")
	eq(GcNum.fmt_f64(_f("0.000000001")), "0.000000001")
	eq(GcNum.fmt_f64(_f("0.0000000001")), "1e-10")


func test_fmt_f64_cases() -> void:
	eq(GcNum.fmt_f64(0.0), "0")
	eq(GcNum.fmt_f64(GcNum.from_bits(GcNum.SIGN_BIT)), "0") # -0.0
	eq(GcNum.fmt_f64(_f("0.3")), "0.3")
	eq(GcNum.fmt_f64(_f("-2.5")), "-2.5")
	eq(GcNum.fmt_f64(100.0), "100")
	eq(GcNum.fmt_f64(1.0 / 3.0), "0.333333333333")
	eq(GcNum.fmt_f64(_f("123456789.12345679")), "123456789.123")
	eq(GcNum.fmt_f64(_f("-1e-9")), "-0.000000001")
	eq(GcNum.fmt_f64(_f("-1e-10")), "-1e-10")
	eq(GcNum.fmt_f64(GcNum.from_bits(GcNum.MAX_FINITE_BITS)), "1.79769313486e308")


func test_huge_operands_no_panic() -> void:
	var s := _st()
	_seq(s, "9")
	for _i in 30:
		s.input_digit(9)
	s.input_binary(BinOp.MUL)
	for _i in 30:
		s.input_digit(9)
	s.equals()
	check(s.error == Err.NONE or s.error == Err.OVERFLOW)


func test_sanitize_truncates_hostile_history() -> void:
	var s := _st()
	for i in 150:
		s.history.append({"expr": "e".repeat(1000), "result": str(i).repeat(100), "value": null})
	s.sanitize_persisted()
	eq(s.history.size(), E.MAX_HISTORY)
	for h in s.history:
		check(h["expr"].length() <= E.MAX_PERSIST_STR and h["result"].length() <= E.MAX_PERSIST_STR)


func test_bare_equals_records_no_history() -> void:
	var s := _st()
	s.equals()
	s.equals()
	check(s.history.is_empty())
	eq(s.result_display(), "0")
	# A real computation still records, and repeat-equals keeps recording one
	# entry per press.
	_seq(s, "2+3=")
	eq(s.history.size(), 1)
	s.equals()
	eq(s.history.size(), 2)


func test_recall_and_ans_clamp_huge_result() -> void:
	var s := _st()
	s.history.append({"expr": "x", "result": "9".repeat(500), "value": null})
	s.recall_history(0)
	check(s.entry().length() <= 32)
	s.clear_entry()
	s.input_ans()
	check(s.entry().length() <= 32)


func test_rapid_state_churn_no_panic() -> void:
	var s := _st()
	s.set_mode(Mode.SCIENTIFIC)
	for i in 500:
		match i % 11:
			0: s.input_binary(BinOp.ADD)
			1: s.input_binary(BinOp.MUL)
			2: s.input_digit(i % 10)
			3: s.input_unary(UnaryOp.SQRT)
			4: s.input_lparen()
			5: s.input_rparen()
			6: s.input_percent()
			7: s.equals()
			8: s.backspace()
			9: s.toggle_sign()
			_: s.input_dot()
	s.result_display()
	check(true)


# ---- additions beyond the Rust suite ----

func test_truncate_str_respects_utf8_boundaries() -> void:
	eq(E.truncate_str("abc", 5), "abc")
	eq(E.truncate_str("abcdef", 3), "abc")
	eq(E.truncate_str("ééé", 5), "éé") # 2 bytes each: the third would split
	eq(E.truncate_str("π", 1), "")


func test_checked_integer_edges() -> void:
	var r := E.apply_binary(BinOp.ADD, E.INT_MAX, 1)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.SUB, E.INT_MIN, 1)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.MUL, E.INT_MIN, -1)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.DIV, E.INT_MIN, -1)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.MOD, E.INT_MIN, -1)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.POW, 2, 62)
	eq(r[1], 4611686018427387904)
	r = E.apply_binary(BinOp.POW, 2, 63)
	eq(r[0], Err.OVERFLOW)
	r = E.apply_binary(BinOp.POW, -2, 63)
	eq(r[1], E.INT_MIN)
	r = E.apply_binary(BinOp.ADD, 9007199254740993, 1)
	eq(r[1], 9007199254740994) # beyond f64 precision, still exact
