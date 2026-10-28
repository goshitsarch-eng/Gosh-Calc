class_name GcPalette
extends RefCounted
## Design tokens (from the original stylesheet) and the Godot Theme built from
## them. Swapping the Theme on the root control restyles the whole UI, which is
## how System/Light/Dark switch live without rebuilding any widget.

const LIGHT := {
	"bg": "#f4f5f6", "panel": "#ffffff", "key": "#e7e9ec", "text": "#182027", "muted": "#56636e",
	"line": "#dce1e5", "accent": "#087f8d", "accent_text": "#ffffff", "error": "#b7253b",
}
const DARK := {
	"bg": "#171b20", "panel": "#21272e", "key": "#303943", "text": "#edf3f7", "muted": "#aebac5",
	"line": "#3d4751", "accent": "#62d4df", "accent_text": "#10272a", "error": "#ff8997",
}

static var _fonts := {}


static func tokens(dark: bool) -> Dictionary:
	var src: Dictionary = DARK if dark else LIGHT
	var out := {}
	for k in src:
		out[k] = Color(src[k])
	return out


static func font(weight: String) -> Font:
	if _fonts.is_empty():
		var dejavu: Font = load("res://assets/fonts/DejaVuSans.ttf")
		var mono: Font = load("res://assets/fonts/DejaVuSansMono.ttf")
		for pair in [["regular", "Inter-Regular"], ["medium", "Inter-Medium"], ["semibold", "Inter-SemiBold"]]:
			var v := FontVariation.new()
			v.base_font = load("res://assets/fonts/%s.otf" % pair[1])
			v.fallbacks = [dejavu]
			_fonts[pair[0]] = v
		# the big result line: medium weight, tabular figures, slightly tight
		var result := FontVariation.new()
		result.base_font = load("res://assets/fonts/Inter-Medium.otf")
		result.fallbacks = [dejavu]
		result.opentype_features = {"tnum": 1}
		result.spacing_glyph = -1
		_fonts["result"] = result
		var tabular := FontVariation.new()
		tabular.base_font = load("res://assets/fonts/Inter-Regular.otf")
		tabular.fallbacks = [dejavu]
		tabular.opentype_features = {"tnum": 1}
		_fonts["tabular"] = tabular
		_fonts["mono"] = mono
	return _fonts[weight]


static func _flat(color: Color, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s


static func _brighten(c: Color, factor: float = 1.08) -> Color:
	return Color(minf(c.r * factor, 1.0), minf(c.g * factor, 1.0), minf(c.b * factor, 1.0), c.a)


## A button type variation: background per state, text colour, font, radius.
static func _button_variant(theme: Theme, name: String, bg: Color, fg: Color, radius: int,
		font_size: int, weight: String, pad: Vector2i, focus_color: Color) -> void:
	theme.set_type_variation(name, "Button")
	var make := func(color: Color, top_extra: int) -> StyleBoxFlat:
		var s := _flat(color, radius)
		s.content_margin_left = pad.x
		s.content_margin_right = pad.x
		s.content_margin_top = pad.y + top_extra
		s.content_margin_bottom = pad.y
		return s
	theme.set_stylebox("normal", name, make.call(bg, 0))
	theme.set_stylebox("hover", name, make.call(_brighten(bg), 0))
	theme.set_stylebox("pressed", name, make.call(_brighten(bg), 2)) # sinks by 1px like the original
	theme.set_stylebox("hover_pressed", name, make.call(_brighten(bg), 2))
	theme.set_stylebox("disabled", name, make.call(bg, 0))
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(3)
	ring.border_color = focus_color
	ring.set_corner_radius_all(radius + 2)
	ring.set_expand_margin_all(2)
	theme.set_stylebox("focus", name, ring)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		theme.set_color(state, name, fg)
	theme.set_font("font", name, font(weight))
	theme.set_font_size("font_size", name, font_size)


static func make_theme(dark: bool) -> Theme:
	var c := tokens(dark)
	var theme := Theme.new()
	theme.default_font = font("regular")
	theme.default_font_size = 14

	# plain controls
	theme.set_color("font_color", "Label", c["text"])
	theme.set_font("font", "Label", font("regular"))
	theme.set_stylebox("normal", "Label", StyleBoxEmpty.new())
	for variant in [["MutedLabel", c["muted"]], ["ErrorLabel", c["error"]], ["AccentLabel", c["accent"]]]:
		theme.set_type_variation(variant[0], "Label")
		theme.set_color("font_color", variant[0], variant[1])
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", font("semibold"))
	theme.set_font_size("font_size", "HeadingLabel", 17)
	theme.set_type_variation("ResultLabel", "Label")
	theme.set_font("font", "ResultLabel", font("result"))
	theme.set_color("font_color", "ResultLabel", c["text"])
	theme.set_type_variation("BaseValue", "Label")
	theme.set_font("font", "BaseValue", font("mono"))
	theme.set_color("font_color", "BaseValue", c["text"])
	theme.set_type_variation("BaseValueActive", "Label")
	theme.set_font("font", "BaseValueActive", font("mono"))
	theme.set_color("font_color", "BaseValueActive", c["accent_text"])
	theme.set_type_variation("BaseCaption", "Label")
	theme.set_color("font_color", "BaseCaption", Color(c["text"], 0.8))
	theme.set_type_variation("BaseCaptionActive", "Label")
	theme.set_color("font_color", "BaseCaptionActive", Color(c["accent_text"], 0.8))

	# buttons
	var accent: Color = c["accent"]
	_button_variant(theme, "KeyButton", c["key"], c["text"], 30, 17, "regular", Vector2i(4, 9), accent)
	_button_variant(theme, "FnKeyButton", c["key"], c["text"], 30, 13, "regular", Vector2i(4, 9), accent)
	_button_variant(theme, "EqualsKeyButton", accent, c["accent_text"], 30, 24, "regular", Vector2i(4, 9), accent)
	_button_variant(theme, "GhostButton", Color(0, 0, 0, 0), c["text"], 8, 20, "regular", Vector2i(6, 2), accent)
	_button_variant(theme, "SmallGhostButton", Color(0, 0, 0, 0), c["muted"], 8, 12, "regular", Vector2i(6, 2), accent)
	_button_variant(theme, "ModeButton", c["key"], c["text"], 24, 13, "regular", Vector2i(4, 11), accent)
	_button_variant(theme, "ModeButtonActive", accent, c["accent_text"], 24, 13, "semibold", Vector2i(4, 11), accent)
	_button_variant(theme, "ChoiceButton", c["key"], c["text"], 8, 14, "regular", Vector2i(5, 10), accent)
	_button_variant(theme, "ChoiceButtonActive", accent, c["accent_text"], 8, 14, "semibold", Vector2i(5, 10), accent)
	_button_variant(theme, "ReadoutButton", c["key"], c["text"], 8, 12, "regular", Vector2i(10, 8), accent)
	_button_variant(theme, "ReadoutButtonActive", accent, c["accent_text"], 8, 12, "semibold", Vector2i(10, 8), accent)
	_button_variant(theme, "PanelButton", c["key"], c["text"], 9, 14, "regular", Vector2i(14, 10), accent)
	_button_variant(theme, "DoneButton", accent, c["accent_text"], 9, 14, "regular", Vector2i(14, 10), accent)
	_button_variant(theme, "HistoryEntryButton", Color(0, 0, 0, 0), c["text"], 8, 14, "regular", Vector2i(8, 12), accent)

	# containers
	var panel := _flat(c["panel"], 14)
	panel.set_border_width_all(1)
	panel.border_color = c["line"]
	panel.set_content_margin_all(14)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("DialogPanel", "PanelContainer")
	var dialog := _flat(c["panel"], 18)
	dialog.set_border_width_all(1)
	dialog.border_color = c["line"]
	dialog.set_content_margin_all(22)
	dialog.shadow_color = Color(0, 0, 0, 0.33)
	dialog.shadow_size = 40
	dialog.shadow_offset = Vector2(0, 20)
	theme.set_stylebox("panel", "DialogPanel", dialog)
	theme.set_type_variation("NoticePanel", "PanelContainer")
	var notice := _flat(c["panel"], 12)
	notice.set_border_width_all(1)
	notice.border_color = c["line"]
	notice.content_margin_left = 12
	notice.content_margin_right = 4
	notice.content_margin_top = 4
	notice.content_margin_bottom = 4
	notice.shadow_color = Color(0, 0, 0, 0.2)
	notice.shadow_size = 24
	notice.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "NoticePanel", notice)
	theme.set_type_variation("Fieldset", "PanelContainer")
	var fieldset := _flat(Color(0, 0, 0, 0), 12)
	fieldset.set_border_width_all(1)
	fieldset.border_color = c["line"]
	fieldset.set_content_margin_all(14)
	theme.set_stylebox("panel", "Fieldset", fieldset)
	theme.set_type_variation("MenuRule", "Panel")
	theme.set_stylebox("panel", "MenuRule", _flat(c["line"], 0))
	theme.set_type_variation("PlainPanel", "PanelContainer")
	theme.set_stylebox("panel", "PlainPanel", StyleBoxEmpty.new())
	theme.set_type_variation("BrandLabel", "Label")
	theme.set_color("font_color", "BrandLabel", c["accent_text"])
	theme.set_font_size("font_size", "BrandLabel", 22)
	theme.set_type_variation("BrandMark", "PanelContainer")
	theme.set_stylebox("panel", "BrandMark", _flat(accent, 9))

	# scrollbars: thin, unobtrusive
	for kind in ["VScrollBar", "HScrollBar"]:
		var grabber := _flat(Color(c["muted"], 0.45), 4)
		var grabber_hi := _flat(Color(c["muted"], 0.75), 4)
		theme.set_stylebox("grabber", kind, grabber)
		theme.set_stylebox("grabber_highlight", kind, grabber_hi)
		theme.set_stylebox("grabber_pressed", kind, grabber_hi)
		theme.set_stylebox("scroll", kind, StyleBoxEmpty.new())
		theme.set_stylebox("scroll_focus", kind, StyleBoxEmpty.new())
	theme.set_constant("scrollbar_h_separation", "ScrollContainer", 0)
	theme.set_constant("scrollbar_v_separation", "ScrollContainer", 0)

	# tooltips
	var tip := _flat(c["panel"], 6)
	tip.set_border_width_all(1)
	tip.border_color = c["line"]
	tip.content_margin_left = 8
	tip.content_margin_right = 8
	tip.content_margin_top = 4
	tip.content_margin_bottom = 4
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", c["text"])
	theme.set_font_size("font_size", "TooltipLabel", 12)

	# menu bar and its drop-down menus
	var bar := _flat(c["bg"], 0)
	bar.set_content_margin_all(0)
	bar.content_margin_left = 8
	bar.content_margin_right = 8
	bar.content_margin_top = 5
	bar.content_margin_bottom = 5
	for state in ["normal", "disabled"]:
		theme.set_stylebox(state, "MenuBar", bar)
	for state in ["hover", "pressed", "hover_pressed"]:
		var hover_bar := bar.duplicate()
		hover_bar.bg_color = c["key"]
		hover_bar.set_corner_radius_all(4)
		theme.set_stylebox(state, "MenuBar", hover_bar)
	theme.set_stylebox("normal_mirrored", "MenuBar", bar)
	theme.set_stylebox("hover_mirrored", "MenuBar", bar)
	theme.set_stylebox("pressed_mirrored", "MenuBar", bar)
	theme.set_stylebox("hover_pressed_mirrored", "MenuBar", bar)
	theme.set_stylebox("disabled_mirrored", "MenuBar", bar)
	theme.set_color("font_color", "MenuBar", c["text"])
	theme.set_color("font_hover_color", "MenuBar", c["text"])
	theme.set_color("font_pressed_color", "MenuBar", c["text"])
	theme.set_color("font_hover_pressed_color", "MenuBar", c["text"])
	theme.set_color("font_focus_color", "MenuBar", c["text"])
	theme.set_color("font_disabled_color", "MenuBar", c["muted"])
	theme.set_constant("h_separation", "MenuBar", 4)
	var popup := _flat(c["panel"], 6)
	popup.set_border_width_all(1)
	popup.border_color = c["line"]
	popup.set_content_margin_all(4)
	popup.shadow_color = Color(0, 0, 0, 0.25)
	popup.shadow_size = 10
	theme.set_stylebox("panel", "PopupMenu", popup)
	var hover := _flat(c["key"], 4)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_stylebox("separator", "PopupMenu", _separator(c["line"]))
	theme.set_stylebox("labeled_separator_left", "PopupMenu", _separator(c["line"]))
	theme.set_stylebox("labeled_separator_right", "PopupMenu", _separator(c["line"]))
	for key in ["font_color", "font_hover_color", "font_accelerator_color"]:
		theme.set_color(key, "PopupMenu", c["text"] if key != "font_accelerator_color" else c["muted"])
	theme.set_color("font_disabled_color", "PopupMenu", Color(c["muted"], 0.6))
	theme.set_color("font_separator_color", "PopupMenu", c["muted"])
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_constant("item_start_padding", "PopupMenu", 8)
	theme.set_constant("item_end_padding", "PopupMenu", 8)
	return theme


static func _separator(color: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = 1
	return s
