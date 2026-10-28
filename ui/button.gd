class_name GcButton
extends Button
## A themed button. Keyboard focus shows a ring (like :focus-visible); a mouse
## click activates the button without leaving it focused, so Enter keeps
## meaning "equals" after clicking a key.

## True after the last input was a mouse/touch event: programmatic focus (e.g.
## into a dialog) then shows no ring, like CSS :focus-visible.
static var pointer_mode := true

var _from_pointer := false


func _init(variation: String = "KeyButton", label: String = "", tip: String = "") -> void:
	theme_type_variation = variation
	text = label
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not tip.is_empty():
		tooltip_text = tip
		accessibility_name = tip
	pressed.connect(_after_press)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER:
		show_ring(not pointer_mode)


func show_ring(visible_ring: bool) -> void:
	if visible_ring:
		remove_theme_stylebox_override("focus")
	else:
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_from_pointer = true
	elif event is InputEventKey:
		_from_pointer = false


func _after_press() -> void:
	if _from_pointer:
		_release_if_present.call_deferred()


func _release_if_present() -> void:
	# a click can rebuild the list that contains this button (history recall)
	if is_inside_tree() and has_focus():
		release_focus()


## Disabled buttons fade as a whole (opacity .38), as in the original design.
func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	modulate.a = 1.0 if enabled else 0.38
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW


func set_variation(variation: String) -> void:
	theme_type_variation = variation
