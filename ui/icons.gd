class_name GcIcon
extends Control
## Small vector icons for glyphs that no bundled font provides.

@export var kind := "copy"
@export var color_name := "font_color"
@export var type_name := "Label"


func _init(icon_kind: String = "copy") -> void:
	kind = icon_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(20, 20)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var color := get_theme_color(color_name, type_name)
	var s := minf(size.x, size.y) / 20.0
	var origin := (size - Vector2(20, 20) * s) * 0.5
	var w := 1.3 * s
	if kind == "copy":
		# two joined squares, like the original "⧉" glyph
		var back := Rect2(origin + Vector2(3, 3) * s, Vector2(10, 10) * s)
		var front := Rect2(origin + Vector2(7, 7) * s, Vector2(10, 10) * s)
		draw_rect(back, color, false, w)
		draw_rect(front, color, false, w)
