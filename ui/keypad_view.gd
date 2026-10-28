class_name GcKeypadView
extends Container
## The keypad for the current mode. Standard and programmer modes are one grid
## (4 and 6 columns); scientific is two 4-column grids side by side, stacked
## when the window is narrow.

signal command_requested(command: Dictionary)

const E := preload("res://core/engine.gd")
const PAD := 3

var _mode: int = -1
var _grids: Array = []
var _buttons: Array = [] # [GcButton, command]
var _window_width := 460.0


func _init() -> void:
	name = "Keypad"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_window_width(width: float) -> void:
	if width == _window_width:
		return
	_window_width = width
	if _mode >= 0:
		_apply_metrics()
	update_minimum_size()
	queue_sort()


func _stacked() -> bool:
	return _mode == E.Mode.SCIENTIFIC and _window_width <= 700.0


func _gap() -> int:
	return 5 if _window_width <= 420.0 else 7


func rebuild(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	for g in _grids:
		g.queue_free()
		remove_child(g)
	_grids.clear()
	_buttons.clear()
	match mode:
		E.Mode.STANDARD:
			_add_grid("Standard keypad", GcKeypadDefs.standard(), 4)
		E.Mode.SCIENTIFIC:
			_add_grid("Scientific functions", GcKeypadDefs.scientific_functions(), 4, 6)
			_add_grid("Scientific numeric keypad", GcKeypadDefs.scientific_numeric(), 4, 6)
		_:
			_add_grid("Programmer keypad", GcKeypadDefs.programmer(), 6)
	_apply_metrics()
	update_minimum_size()
	queue_sort()


func _add_grid(grid_name: String, keys: Array, columns: int, rows: int = 0) -> void:
	var grid := GcKeyGrid.new()
	grid.name = grid_name.replace(" ", "")
	grid.accessibility_name = grid_name
	grid.set_metrics(columns, _gap(), rows)
	add_child(grid)
	_grids.append(grid)
	for key in keys:
		var variation := "KeyButton"
		match key["kind"]:
			"function":
				variation = "FnKeyButton"
			"equals":
				variation = "EqualsKeyButton"
		var button := GcButton.new(variation, key["label"], key["name"])
		button.name = key["name"]
		button.set_meta("command_name", key["name"])
		if key["kind"] == "equals" and _mode == E.Mode.PROGRAMMER:
			button.set_meta("span", 2)
		var command: Dictionary = key["command"]
		button.pressed.connect(func() -> void: command_requested.emit(command))
		grid.add_child(button)
		_buttons.append([button, command])


func _apply_metrics() -> void:
	for g in _grids:
		g.set_metrics(g.columns, _gap(), g.fixed_rows)
	# in narrow windows every programmer key (including "=") uses a 12px font
	for pair in _buttons:
		var button: GcButton = pair[0]
		if _mode == E.Mode.PROGRAMMER and _window_width <= 420.0:
			button.add_theme_font_size_override("font_size", 12)
		else:
			button.remove_theme_font_size_override("font_size")


## Enables or disables keys according to the shared command rules.
func refresh(app: GcAppState) -> void:
	for pair in _buttons:
		(pair[0] as GcButton).set_enabled(app.enabled(pair[1]))


func _get_minimum_size() -> Vector2:
	if _stacked():
		return Vector2(0, 620)
	return Vector2(0, 320)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()


func _layout() -> void:
	if _grids.is_empty():
		return
	var area := Rect2(Vector2(PAD, PAD), size - Vector2(PAD * 2, PAD * 2))
	if _mode == E.Mode.SCIENTIFIC:
		var gap := float(_gap())
		if _stacked():
			var h := (area.size.y - gap) / 2.0
			fit_child_in_rect(_grids[0], Rect2(area.position, Vector2(area.size.x, h)))
			fit_child_in_rect(_grids[1], Rect2(area.position + Vector2(0, h + gap), Vector2(area.size.x, h)))
		else:
			var w := (area.size.x - gap) / 2.0
			fit_child_in_rect(_grids[0], Rect2(area.position, Vector2(w, area.size.y)))
			fit_child_in_rect(_grids[1], Rect2(area.position + Vector2(w + gap, 0), Vector2(w, area.size.y)))
	else:
		fit_child_in_rect(_grids[0], area)
