class_name GcDialogView
extends Control
## Modal Settings / About / Keyboard-shortcuts dialog over a dimmed backdrop.

signal command_requested(command: Dictionary)

const E := preload("res://core/engine.gd")

var _backdrop: ColorRect
var _scroll: ScrollContainer
var _panel: PanelContainer
var _dialog: int = GcAppState.Dialog.NONE
var _theme_pref: int = -1
var _built_for := ""


func _init() -> void:
	name = "DialogLayer"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.4)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			command_requested.emit(GcCommands.close_dialog()))
	add_child(_backdrop)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DialogPanel"
	_panel.name = "Dialog"
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	resized.connect(_layout)


func is_open() -> bool:
	return visible


static func _title(dialog: int) -> String:
	match dialog:
		GcAppState.Dialog.SETTINGS:
			return "Settings"
		GcAppState.Dialog.ABOUT:
			return "About Gosh Calc"
		_:
			return "Keyboard shortcuts"


func refresh(app: GcAppState) -> void:
	var dialog := app.dialog
	if dialog == GcAppState.Dialog.NONE:
		visible = false
		_dialog = dialog
		return
	var signature := "%d|%d" % [dialog, app.theme]
	if signature != _built_for:
		_build(app)
		_built_for = signature
	var opening := not visible
	visible = true
	if opening or _dialog != dialog:
		_dialog = dialog
		_layout()
		_focus_first.call_deferred()


func _focus_first() -> void:
	var buttons := focusable_buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()


## Buttons inside the dialog in tab order (used for the focus trap).
func focusable_buttons() -> Array:
	var out := []
	_collect_buttons(_panel, out)
	return out


func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is BaseButton and not child.disabled and child.is_visible_in_tree():
			out.append(child)
		_collect_buttons(child, out)


func _build(app: GcAppState) -> void:
	for child in _scroll.get_children():
		_scroll.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = _title(app.dialog)
	title.theme_type_variation = "HeadingLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.accessibility_name = title.text
	heading.add_child(title)
	var close := GcButton.new("GhostButton", "×", "Close dialog")
	close.name = "CloseDialog"
	close.custom_minimum_size = Vector2(32, 32)
	close.pressed.connect(func() -> void: command_requested.emit(GcCommands.close_dialog()))
	heading.add_child(close)
	match app.dialog:
		GcAppState.Dialog.SETTINGS:
			_build_settings(box, app)
		GcAppState.Dialog.ABOUT:
			_build_about(box)
		_:
			_build_shortcuts(box)
	var done_row := HBoxContainer.new()
	var done_pad := Control.new()
	done_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_row.add_child(done_pad)
	var done := GcButton.new("DoneButton", "Done")
	done.name = "DialogDone"
	done.pressed.connect(func() -> void: command_requested.emit(GcCommands.close_dialog()))
	done_row.add_child(done)
	box.add_child(_gap(20))
	box.add_child(done_row)


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _paragraph(text: String, variation: String = "Label") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_constant_override("line_spacing", 6)
	return l


func _build_settings(box: VBoxContainer, app: GcAppState) -> void:
	box.add_child(_gap(20))
	var fieldset := PanelContainer.new()
	fieldset.theme_type_variation = "Fieldset"
	box.add_child(fieldset)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	fieldset.add_child(col)
	var legend := Label.new()
	legend.text = "Appearance"
	legend.theme_type_variation = "MutedLabel"
	col.add_child(legend)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for pref in [GcAppState.ThemePref.SYSTEM, GcAppState.ThemePref.LIGHT, GcAppState.ThemePref.DARK]:
		var b := GcButton.new("ChoiceButtonActive" if app.theme == pref else "ChoiceButton",
				GcAppState.theme_label(pref))
		b.name = "Theme" + GcAppState.theme_css(pref).capitalize()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("theme_choice", GcAppState.theme_css(pref))
		b.pressed.connect(func() -> void: command_requested.emit(GcCommands.set_theme(pref)))
		row.add_child(b)
	box.add_child(_gap(8))
	box.add_child(_paragraph("Mode, angle unit, history, appearance and window size are saved automatically."))


func _build_about(box: VBoxContainer) -> void:
	var mark := Label.new()
	mark.text = "="
	mark.theme_type_variation = "AccentLabel"
	mark.add_theme_font_size_override("font_size", 44)
	box.add_child(_gap(15))
	box.add_child(mark)
	var heading := Label.new()
	heading.text = "Gosh Calc " + GcApp.version()
	heading.theme_type_variation = "HeadingLabel"
	heading.add_theme_font_size_override("font_size", 19)
	box.add_child(heading)
	box.add_child(_gap(8))
	box.add_child(_paragraph("A standard, scientific and programmer calculator. Built with Godot Engine."))
	box.add_child(_paragraph("Copyright © 2026 goshitsarch-eng · MIT license"))
	var muted := _paragraph("An early preview of the cross-platform edition.", "MutedLabel")
	muted.add_theme_font_size_override("font_size", 12)
	box.add_child(muted)


func _build_shortcuts(box: VBoxContainer) -> void:
	box.add_child(_gap(20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	var rows := [
		["0–9 / A–F", "Enter digits; A–F in programmer HEX"],
		["+ − * / ^ %", "Arithmetic; ^ is XOR in programmer mode"],
		["Enter / =", "Evaluate; press again to repeat"],
		["Esc / Delete / Backspace", "Clear all / clear entry / delete digit"],
		["( ) ! & | < > ~", "Parentheses, factorial and bitwise operators"],
		["p", "π in scientific mode"],
		["Ctrl/⌘ C", "Copy result (Ctrl+Insert also works)"],
		[GcApp.history_shortcut_label(), "History"],
		["Ctrl/⌘ 1, 2, 3", "Standard, scientific, programmer"],
		["Ctrl/⌘ , / F1", "Settings / this shortcut guide"],
	]
	for r in rows:
		var dt := Label.new()
		dt.text = r[0]
		dt.add_theme_font_override("font", GcPalette.font("semibold"))
		dt.add_theme_font_size_override("font_size", 12)
		dt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dt.custom_minimum_size = Vector2(128, 0)
		grid.add_child(dt)
		var dd := Label.new()
		dd.text = r[1]
		dd.theme_type_variation = "MutedLabel"
		dd.add_theme_font_size_override("font_size", 12)
		dd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dd.custom_minimum_size = Vector2(120, 0)
		grid.add_child(dd)


var _layout_serial := 0


func _layout() -> void:
	if not visible:
		return
	var margin := 20.0
	var avail := size - Vector2(margin * 2, margin * 2)
	var width := minf(500.0, maxf(avail.x, 120.0))
	_scroll.custom_minimum_size = Vector2(width - 44.0, 0)
	_panel.size = Vector2(width, 0)
	_panel.position = Vector2((size.x - width) * 0.5, _panel.position.y)
	_measure.call_deferred(_layout_serial + 1)
	_layout_serial += 1


## Autowrapped labels only report their wrapped height once they have a width,
## which takes a couple of frames; hide the panel until it is measured.
func _measure(serial: int) -> void:
	_panel.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if serial != _layout_serial or not visible:
		return
	var margin := 20.0
	var avail_h := maxf(size.y - margin * 2, 120.0)
	var content: Control = _scroll.get_child(0) if _scroll.get_child_count() > 0 else null
	var content_h := 0.0 if content == null else content.get_combined_minimum_size().y
	var height := minf(content_h + 44.0, avail_h)
	_scroll.custom_minimum_size.y = height - 44.0
	_panel.size = Vector2(_panel.size.x, height)
	_panel.position = ((size - _panel.size) * 0.5).round()
	_panel.modulate.a = 1.0
