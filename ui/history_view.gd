class_name GcHistoryView
extends PanelContainer
## The calculation history drawer.

signal command_requested(command: Dictionary)

var _list: VBoxContainer
var _clear: GcButton
var _signature := ""


func _init() -> void:
	name = "History"
	accessibility_name = "Calculation history"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = "History"
	title.theme_type_variation = "HeadingLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := GcButton.new("GhostButton", "×", "Close history")
	close.name = "CloseHistory"
	close.custom_minimum_size = Vector2(32, 32)
	close.pressed.connect(func() -> void: command_requested.emit(GcCommands.toggle_history()))
	heading.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	box.add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_clear = GcButton.new("PanelButton", "Clear history")
	_clear.name = "ClearHistory"
	_clear.pressed.connect(func() -> void: command_requested.emit(GcCommands.clear_history()))
	box.add_child(_clear)


func refresh(app: GcAppState) -> void:
	var history := app.calc.history
	var signature := str(history.size()) + "|" + (str(history[0]) if not history.is_empty() else "")
	for h in history:
		signature += h["expr"] + h["result"]
	_clear.set_enabled(app.enabled(GcCommands.clear_history()))
	if signature == _signature:
		return
	_signature = signature
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if history.is_empty():
		var empty := Label.new()
		empty.text = "Your calculations will appear here."
		empty.theme_type_variation = "MutedLabel"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 24)
		pad.add_theme_constant_override("margin_bottom", 24)
		pad.add_theme_constant_override("margin_left", 10)
		pad.add_theme_constant_override("margin_right", 10)
		pad.add_child(empty)
		_list.add_child(pad)
		return
	for i in history.size():
		_list.add_child(_make_entry(i, history[i]))


func _make_entry(index: int, entry: Dictionary) -> Control:
	var holder := PanelContainer.new()
	holder.theme_type_variation = "PlainPanel"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.name = "Entry%d" % index
	var button := GcButton.new("HistoryEntryButton", "", "Recall " + entry["result"])
	button.accessibility_name = "Recall %s = %s" % [entry["expr"], entry["result"]]
	button.pressed.connect(func() -> void: command_requested.emit(GcCommands.recall(index)))
	holder.add_child(button)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 5)
	var expr := Label.new()
	expr.text = entry["expr"]
	expr.theme_type_variation = "MutedLabel"
	expr.add_theme_font_size_override("font_size", 12)
	expr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	expr.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	expr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var result := Label.new()
	result.text = "= " + entry["result"]
	result.add_theme_font_override("font", GcPalette.font("medium"))
	result.add_theme_font_size_override("font_size", 18)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	result.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(expr)
	box.add_child(result)
	margin.add_child(box)
	holder.add_child(margin)
	return holder
