class_name GcScrollText
extends Control
## One line of text clipped to its box. It shows the end of the text (where you
## are typing) and the mouse wheel scrolls to the beginning, like the original
## `overflow-x: auto` result line. Right- or left-aligned when it fits.

@export var align_right := true
@export var type_name := "Label"
@export var font_size := 14
@export var color_name := "font_color"

var text := "":
	set(value):
		if value == text:
			return
		text = value
		_user_scrolled = false
		tooltip_text = value
		queue_redraw()

var _scroll := 0.0
var _user_scrolled := false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


func _font() -> Font:
	return get_theme_font("font", type_name)


func _get_minimum_size() -> Vector2:
	return Vector2(0, ceilf(_font().get_height(font_size)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		update_minimum_size()
		queue_redraw()


func set_font_size(value: int) -> void:
	if value != font_size:
		font_size = value
		update_minimum_size()
		queue_redraw()


func _text_width() -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _draw() -> void:
	var font := _font()
	var width := _text_width()
	var overflow := maxf(width - size.x, 0.0)
	var x := 0.0
	if overflow > 0.0:
		# end of the text by default (what you are typing), or where the user scrolled
		if not _user_scrolled:
			_scroll = overflow if align_right else 0.0
		_scroll = clampf(_scroll, 0.0, overflow)
		x = -_scroll
	elif align_right:
		x = size.x - width
	var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			get_theme_color(color_name, type_name))


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var overflow := maxf(_text_width() - size.x, 0.0)
	if overflow <= 0.0:
		return
	var step := 0.0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			step = -48.0
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			step = 48.0
	if step != 0.0:
		_user_scrolled = true
		_scroll = clampf(_scroll + step, 0.0, overflow)
		queue_redraw()
		accept_event()
