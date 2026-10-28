extends GcTestCase
## Port of tests/integration.rs: original workflows through the shared dispatcher.

const E := preload("res://core/engine.gd")
const C := preload("res://core/commands.gd")
const BinOp := E.BinOp
const UnaryOp := E.UnaryOp
const Mode := E.Mode
const Base := E.Base


func _run(app: GcAppState, commands: Array) -> void:
	for c in commands:
		app.dispatch(c)


func test_flow_calculate_and_recall() -> void:
	var app := GcAppState.new()
	_run(app, [C.digit(1), C.digit(2), C.binary(BinOp.ADD), C.digit(3), C.binary(BinOp.MUL), C.digit(4), C.equals()])
	eq(app.calc.result_display(), "24") # precedence: 12 + 3*4
	eq(app.calc.history.size(), 1)
	eq(app.calc.history[0]["result"], "24")
	# start a new calc, recall the previous result into it
	_run(app, [C.digit(1), C.digit(0), C.binary(BinOp.SUB), C.recall(0), C.equals()])
	eq(app.calc.result_display(), "-14") # 10 - 24
	eq(app.calc.history.size(), 2)


func test_flow_scientific() -> void:
	var app := GcAppState.new()
	app.calc.set_mode(Mode.SCIENTIFIC)
	_run(app, [C.lparen(), C.digit(2), C.binary(BinOp.ADD), C.digit(3), C.rparen(), C.binary(BinOp.MUL), C.digit(4), C.equals()])
	eq(app.calc.result_display(), "20")
	_run(app, [C.unary(UnaryOp.SQRT)]) # sqrt of result, then squared again
	_run(app, [C.unary(UnaryOp.SQUARE)])
	eq(app.calc.result_display(), "20")


func test_flow_programmer() -> void:
	var app := GcAppState.new()
	app.calc.set_mode(Mode.PROGRAMMER)
	_run(app, [C.set_base(Base.HEX), C.digit(15), C.digit(15), C.binary(BinOp.ADD), C.digit(1), C.equals()])
	eq(app.calc.result_display(), "100") # 0xFF + 1 = 0x100
	eq(app.calc.base_readout(), ["100", "256", "400", "100000000"])
	_run(app, [C.set_base(Base.DEC)])
	eq(app.calc.result_display(), "256")


func test_flow_error_recovery() -> void:
	var app := GcAppState.new()
	_run(app, [C.digit(5), C.binary(BinOp.DIV), C.digit(0), C.equals()])
	eq(app.calc.result_display(), "Error")
	_run(app, [C.digit(9), C.equals()]) # any digit clears into a fresh entry
	eq(app.calc.result_display(), "9")


func test_flow_angle_toggle() -> void:
	var app := GcAppState.new()
	app.calc.set_mode(Mode.SCIENTIFIC)
	_run(app, [C.digit(9), C.digit(0), C.unary(UnaryOp.SIN)])
	eq(app.calc.result_display(), "1") # sin(90deg)
	_run(app, [C.toggle_angle(), C.clear_all()])
	_run(app, [C.digit(9), C.digit(0), C.unary(UnaryOp.SIN)])
	eq(app.calc.result_display(), "0.893996663601") # sin(90 rad)


func test_flow_history_clear() -> void:
	var app := GcAppState.new()
	_run(app, [C.digit(2), C.binary(BinOp.ADD), C.digit(2), C.equals()])
	eq(app.calc.history.size(), 1)
	_run(app, [C.clear_history()])
	check(app.calc.history.is_empty())


func test_flow_exp_and_ans() -> void:
	var app := GcAppState.new()
	app.calc.set_mode(Mode.SCIENTIFIC)
	_run(app, [C.digit(5), C.exp(), C.digit(3), C.equals()])
	eq(app.calc.result_display(), "5000") # 5e3
	_run(app, [C.clear_all(), C.ans(), C.binary(BinOp.MUL), C.digit(2), C.equals()])
	eq(app.calc.result_display(), "10000") # Ans * 2


func test_flow_percent() -> void:
	var app := GcAppState.new()
	_run(app, [C.digit(2), C.digit(0), C.digit(0), C.binary(BinOp.ADD), C.digit(1), C.digit(5), C.percent(), C.equals()])
	eq(app.calc.result_display(), "230") # 200 + 15% of 200
