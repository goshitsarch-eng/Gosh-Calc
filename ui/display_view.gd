class_name GcDisplayView
extends MarginContainer
## Expression line, result, error detail, DEG/RAD toggle and the programmer
## base readout.

signal command_requested(command: Dictionary)

const E := preload("res://core/engine.gd")

var _expression: GcScrollText
var _result: GcScrollText
var _error: Label
var _angle_row: HBoxContainer
var _angle: GcButton
var _readout: GridContainer
var _base_buttons := {} # Base -> [GcButton, GcScrollText]


func _init() -> void:
	name = "Display"
	accessibility_name = "Calculator display"
	add_theme_constant_override("margin_left", 7)
	add_theme_constant_override("margin_right", 7)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_bottom", 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_expression = GcScrollText.new()
	_expression.name = "Expression"
	_expression.type_name = "MutedLabel"
	_expression.color_name = "font_color"
	_expression.font_size = 13
	_expression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_expression.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_expression)
	var copy := GcButton.new("GhostButton", "", "Copy result")
	copy.name = "CopyResult"
	copy.custom_minimum_size = Vector2(32, 32)
	var icon := GcIcon.new("copy")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	copy.add_child(icon)
	copy.pressed.connect(func() -> void: command_requested.emit(GcCommands.copy()))
	row.add_child(copy)

	box.add_child(_spacer(5))
	_result = GcScrollText.new()
	_result.name = "Result"
	_result.type_name = "ResultLabel"
	_result.font_size = 42
	_result.accessibility_name = "Result"
	_result.accessibility_live = AccessibilityServer.LIVE_POLITE
	box.add_child(_result)
	box.add_child(_spacer(12))

	_error = Label.new()
	_error.name = "ErrorDetail"
	_error.theme_type_variation = "ErrorLabel"
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_error.visible = false
	box.add_child(_error)

	_angle_row = HBoxContainer.new()
	box.add_child(_angle_row)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_angle_row.add_child(fill)
	_angle = GcButton.new("SmallGhostButton", "DEG", "Toggle angle unit")
	_angle.name = "AngleUnit"
	_angle.custom_minimum_size = Vector2(32, 32)
	_angle.pressed.connect(func() -> void: command_requested.emit(GcCommands.toggle_angle()))
	_angle_row.add_child(_angle)

	_readout = GridContainer.new()
	_readout.columns = 2
	_readout.add_theme_constant_override("h_separation", 6)
	_readout.add_theme_constant_override("v_separation", 6)
	box.add_child(_readout)
	for base in [E.Base.HEX, E.Base.DEC, E.Base.OCT, E.Base.BIN]:
		_readout.add_child(_make_base_button(base))


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _make_base_button(base: int) -> Control:
	var label_text := E.base_label(base)
	var button := GcButton.new("ReadoutButton", "", "Select " + label_text)
	button.name = "Base" + label_text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 52)
	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 10
	inner.offset_right = -10
	inner.offset_top = 8
	inner.offset_bottom = -8
	inner.add_theme_constant_override("separation", 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := Label.new()
	caption.text = label_text
	caption.theme_type_variation = "BaseCaption"
	caption.add_theme_font_size_override("font_size", 11)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(caption)
	var value := GcScrollText.new()
	value.align_right = false
	value.type_name = "BaseValue"
	value.font_size = 12
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(value)
	button.add_child(inner)
	button.pressed.connect(func() -> void: command_requested.emit(GcCommands.set_base(base)))
	_base_buttons[base] = [button, value, caption]
	return button


func set_window_width(width: float) -> void:
	# clamp(26px, 7vw, 42px)
	_result.set_font_size(int(clampf(width * 0.07, 26.0, 42.0)))


func refresh(app: GcAppState) -> void:
	var calc := app.calc
	_expression.text = calc.expression_display()
	var result := calc.result_display()
	_result.text = result
	_result.accessibility_name = "Result " + result
	_error.visible = calc.error != E.CalcError.NONE
	_error.text = E.error_message(calc.error)
	_angle_row.visible = calc.mode == E.Mode.SCIENTIFIC
	_angle.text = "DEG" if calc.angle == E.AngleUnit.DEG else "RAD"
	var readout: Variant = calc.base_readout()
	_readout.visible = readout != null
	if readout != null:
		var order := [E.Base.HEX, E.Base.DEC, E.Base.OCT, E.Base.BIN]
		for i in order.size():
			var parts: Array = _base_buttons[order[i]]
			(parts[0] as GcButton).set_variation("ReadoutButtonActive" if calc.base == order[i] else "ReadoutButton")
			(parts[1] as GcScrollText).text = readout[i]
			(parts[1] as GcScrollText).type_name = "BaseValueActive" if calc.base == order[i] else "BaseValue"
			(parts[1] as GcScrollText).queue_redraw()
			(parts[2] as Label).theme_type_variation = "BaseCaptionActive" if calc.base == order[i] else "BaseCaption"
