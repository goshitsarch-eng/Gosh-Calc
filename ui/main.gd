extends Control
## Gosh Calc application shell. Owns the application state, wires the views to
## the shared command dispatcher, and handles the platform: window geometry and
## HiDPI scaling, native menus, clipboard, theme and settings persistence.

const E := preload("res://core/engine.gd")
const C := preload("res://core/commands.gd")

const MENU_ABOUT := 1
const MENU_SETTINGS := 2
const MENU_QUIT := 3
const MENU_COPY := 4
const MENU_CLEAR := 5
const MENU_STANDARD := 6
const MENU_SCIENTIFIC := 7
const MENU_PROGRAMMER := 8
const MENU_HISTORY := 9
const MENU_SHORTCUTS := 10

const MODES := [
	[E.Mode.STANDARD, "Standard"], [E.Mode.SCIENTIFIC, "Scientific"], [E.Mode.PROGRAMMER, "Programmer"],
]

var app := GcAppState.new()
var store: GcStore = null
var writer: GcWriter = null
var ui_scale := 1.0

var _bg: ColorRect
var _menu_bar: MenuBar
var _margin: MarginContainer
var _vbox: VBoxContainer
var _mode_buttons := {}
var _history_button: GcButton
var _workspace: Control
var _calc_scroll: ScrollContainer
var _calc_content: VBoxContainer
var _display: GcDisplayView
var _keypad: GcKeypadView
var _history: GcHistoryView
var _dialog: GcDialogView
var _notice_panel: PanelContainer
var _notice_label: Label
var _notice_timer: Timer
var _error_timer: Timer
var _underlay_locked := false
var _closed := false


func _ready() -> void:
	var cli := GcApp.cli(OS.get_cmdline_user_args())
	if cli["handled"]:
		if cli["exit_code"] == 0:
			print(cli["output"])
		else:
			printerr(cli["output"])
		_closed = true
		get_tree().quit(cli["exit_code"])
		return
	get_tree().auto_accept_quit = false
	_boot()
	_build_ui()
	_apply_window()
	_apply_theme()
	if DisplayServer.is_dark_mode_supported():
		DisplayServer.set_system_theme_change_callback(_on_system_theme_changed)
	get_window().size_changed.connect(_on_window_resized)
	resized.connect(_relayout)
	refresh()


func _exit_tree() -> void:
	if writer != null:
		writer.close()


# ---------- startup ----------

func _boot() -> void:
	var found := GcStore.discover()
	if found["store"] == null:
		app.notice = found["error"]
		return
	var candidate: GcStore = found["store"]
	var loaded := candidate.load_state()
	if not loaded["error"].is_empty():
		# unreadable/newer/oversized settings are preserved untouched: saving is disabled
		app.notice = loaded["error"]
		return
	app = GcAppState.from_saved(loaded["state"])
	app.notice = loaded["notice"]
	store = candidate
	writer = GcWriter.new(store)


static func _detect_scale() -> float:
	var override := OS.get_environment("GOSH_CALC_SCALE")
	if override.is_valid_float() and override.to_float() > 0.0:
		return clampf(override.to_float(), 0.5, 4.0)
	return maxf(1.0, DisplayServer.screen_get_scale())


func _apply_window() -> void:
	var window := get_window()
	ui_scale = _detect_scale()
	window.title = GcApp.APP_NAME
	window.content_scale_factor = ui_scale
	window.min_size = Vector2i(ceili(360.0 * ui_scale), ceili(480.0 * ui_scale))
	var geometry := GcAppState.bounded_window(app.window)
	var width: float = geometry["width"]
	if app.calc.mode == E.Mode.SCIENTIFIC:
		width = maxf(width, 760.0)
	window.size = Vector2i(roundi(width * ui_scale), roundi(float(geometry["height"]) * ui_scale))
	window.move_to_center()
	if geometry["maximized"]:
		window.mode = Window.MODE_MAXIMIZED


# ---------- construction ----------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_menu_bar = _build_menu_bar()
	var menu_holder := VBoxContainer.new()
	menu_holder.name = "MenuHolder"
	menu_holder.add_theme_constant_override("separation", 0)
	menu_holder.add_child(_menu_bar)
	var rule := Panel.new()
	rule.theme_type_variation = "MenuRule"
	rule.custom_minimum_size = Vector2(0, 1)
	menu_holder.add_child(rule)
	# macOS shows these menus in the system menu bar instead
	menu_holder.visible = not (GcApp.is_macos() and _menu_bar.prefer_global_menu)
	column.add_child(menu_holder)

	_margin = MarginContainer.new()
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_margin)
	_vbox = VBoxContainer.new()
	_margin.add_child(_vbox)
	_vbox.add_child(_build_toolbar())
	_vbox.add_child(_build_mode_nav())

	_workspace = Control.new()
	_workspace.name = "Workspace"
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.clip_contents = false
	_workspace.resized.connect(_layout_workspace)
	_vbox.add_child(_workspace)

	_calc_scroll = ScrollContainer.new()
	_calc_scroll.name = "Calculator"
	_calc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_calc_scroll.accessibility_name = "Calculation"
	_workspace.add_child(_calc_scroll)
	_calc_content = VBoxContainer.new()
	_calc_content.add_theme_constant_override("separation", 16)
	_calc_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 3)
	pad.add_theme_constant_override("margin_right", 3)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_calc_scroll.add_child(pad)
	pad.add_child(_calc_content)
	_calc_scroll.resized.connect(_fit_calc_content)

	_display = GcDisplayView.new()
	_display.command_requested.connect(run)
	_calc_content.add_child(_display)
	_keypad = GcKeypadView.new()
	_keypad.command_requested.connect(run)
	_calc_content.add_child(_keypad)

	_history = GcHistoryView.new()
	_history.command_requested.connect(run)
	_history.visible = false
	_workspace.add_child(_history)

	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_notice_panel = _build_notice()
	overlay.add_child(_notice_panel)
	_dialog = GcDialogView.new()
	_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.command_requested.connect(run)
	overlay.add_child(_dialog)

	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = 2.0
	_notice_timer.timeout.connect(_on_notice_timeout)
	add_child(_notice_timer)
	_error_timer = Timer.new()
	_error_timer.wait_time = 0.3
	_error_timer.autostart = true
	_error_timer.timeout.connect(_poll_writer_errors)
	add_child(_error_timer)


func _build_menu_bar() -> MenuBar:
	var bar := MenuBar.new()
	bar.name = "MenuBar"
	var cmd := KEY_MASK_CMD_OR_CTRL
	var history_accel: int = (KEY_MASK_META | KEY_MASK_SHIFT | KEY_H) if GcApp.is_macos() else (KEY_MASK_CTRL | KEY_H)

	var file := PopupMenu.new()
	file.name = "File"
	file.add_item("About Gosh Calc", MENU_ABOUT)
	file.add_item("Settings…", MENU_SETTINGS, cmd | KEY_COMMA)
	file.add_separator()
	file.add_item("Quit Gosh Calc", MENU_QUIT, cmd | KEY_Q)
	bar.add_child(file)
	var edit := PopupMenu.new()
	edit.name = "Edit"
	edit.add_item("Copy Result", MENU_COPY, cmd | KEY_C)
	edit.add_item("Clear Calculation", MENU_CLEAR)
	bar.add_child(edit)
	var view := PopupMenu.new()
	view.name = "View"
	view.add_item("Standard", MENU_STANDARD, cmd | KEY_1)
	view.add_item("Scientific", MENU_SCIENTIFIC, cmd | KEY_2)
	view.add_item("Programmer", MENU_PROGRAMMER, cmd | KEY_3)
	view.add_separator()
	view.add_item("History", MENU_HISTORY, history_accel)
	bar.add_child(view)
	var help := PopupMenu.new()
	help.name = "Help"
	help.add_item("Keyboard Shortcuts", MENU_SHORTCUTS)
	bar.add_child(help)
	for menu in [file, edit, view, help]:
		menu.id_pressed.connect(_on_menu_item)
	return bar


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "Toolbar"
	bar.add_theme_constant_override("separation", 10)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := PanelContainer.new()
	mark.theme_type_variation = "BrandMark"
	mark.custom_minimum_size = Vector2(30, 30)
	var mark_label := Label.new()
	mark_label.text = "="
	mark_label.theme_type_variation = "BrandLabel"
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_child(mark_label)
	brand.add_child(mark)
	var title := Label.new()
	title.text = GcApp.APP_NAME
	title.add_theme_font_override("font", GcPalette.font("semibold"))
	brand.add_child(title)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(brand)
	var actions := HBoxContainer.new()
	actions.name = "ToolbarActions"
	actions.add_theme_constant_override("separation", 10)
	_history_button = GcButton.new("GhostButton", "↺", "History")
	_history_button.name = "HistoryToggle"
	_history_button.custom_minimum_size = Vector2(32, 32)
	_history_button.pressed.connect(func() -> void: run(C.toggle_history()))
	actions.add_child(_history_button)
	var settings := GcButton.new("GhostButton", "⚙", "Settings")
	settings.name = "SettingsButton"
	settings.custom_minimum_size = Vector2(32, 32)
	settings.pressed.connect(func() -> void: run(C.show_dialog(GcAppState.Dialog.SETTINGS)))
	actions.add_child(settings)
	var shortcuts := GcButton.new("GhostButton", "?", "Keyboard shortcuts")
	shortcuts.name = "ShortcutsButton"
	shortcuts.custom_minimum_size = Vector2(32, 32)
	shortcuts.pressed.connect(func() -> void: run(C.show_dialog(GcAppState.Dialog.SHORTCUTS)))
	actions.add_child(shortcuts)
	bar.add_child(actions)
	return bar


func _build_mode_nav() -> Control:
	var nav := HBoxContainer.new()
	nav.name = "Modes"
	nav.accessibility_name = "Calculator mode"
	nav.add_theme_constant_override("separation", 6)
	for pair in MODES:
		var mode: int = pair[0]
		var button := GcButton.new("ModeButton", pair[1])
		button.name = pair[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: run(C.set_mode(mode)))
		_mode_buttons[mode] = button
		nav.add_child(button)
	return nav


func _build_notice() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Notice"
	panel.theme_type_variation = "NoticePanel"
	panel.visible = false
	panel.accessibility_live = AccessibilityServer.LIVE_POLITE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	_notice_label = Label.new()
	_notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	row.add_child(_notice_label)
	var dismiss := GcButton.new("GhostButton", "×", "Dismiss notification")
	dismiss.name = "DismissNotice"
	dismiss.custom_minimum_size = Vector2(32, 32)
	dismiss.pressed.connect(func() -> void: run(C.dismiss_notice()))
	row.add_child(dismiss)
	return panel


# ---------- commands ----------

## The single entry point for every interaction: keypad, keyboard, menus and
## history all become a command here.
func run(command: Dictionary) -> void:
	if _closed:
		return
	var previous_mode := app.calc.mode
	var effect := app.dispatch(command)
	if command["k"] == C.Kind.SET_THEME:
		_apply_theme()
	if app.calc.mode == E.Mode.SCIENTIFIC and previous_mode != E.Mode.SCIENTIFIC:
		_widen_for_scientific()
	if effect["persist"] and writer != null:
		var message := writer.save(app.saved())
		if not message.is_empty():
			app.notice = message
	if effect["copy"] != null:
		_copy(effect["copy"])
	if effect["quit"]:
		quit_app()
		return
	refresh()


func _copy(text: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		app.notice = "Could not copy: clipboard unavailable"
		return
	DisplayServer.clipboard_set(text)
	app.notice = "Copied"


func quit_app() -> void:
	if _closed:
		return
	_closed = true
	if writer != null:
		writer.close()
		writer = null
	get_tree().quit()


## Flushes settings and stops background work without ending the process
## (lets tests restart the scene within one session).
func quit_app_for_test() -> void:
	_closed = true
	if writer != null:
		writer.close()
		writer = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_remember_window()
		quit_app()


func _on_menu_item(id: int) -> void:
	match id:
		MENU_ABOUT:
			run(C.show_dialog(GcAppState.Dialog.ABOUT))
		MENU_SETTINGS:
			run(C.show_dialog(GcAppState.Dialog.SETTINGS))
		MENU_QUIT:
			run(C.quit())
		MENU_COPY:
			run(C.copy())
		MENU_CLEAR:
			run(C.clear_all())
		MENU_STANDARD:
			run(C.set_mode(E.Mode.STANDARD))
		MENU_SCIENTIFIC:
			run(C.set_mode(E.Mode.SCIENTIFIC))
		MENU_PROGRAMMER:
			run(C.set_mode(E.Mode.PROGRAMMER))
		MENU_HISTORY:
			run(C.toggle_history())
		MENU_SHORTCUTS:
			run(C.show_dialog(GcAppState.Dialog.SHORTCUTS))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		GcButton.pointer_mode = true
	elif event is InputEventKey and event.pressed:
		if GcButton.pointer_mode:
			GcButton.pointer_mode = false
			var focused := get_viewport().gui_get_focus_owner()
			if focused is GcButton:
				focused.show_ring(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key := GcApp.key_name(event)
	if app.dialog != GcAppState.Dialog.NONE:
		if key == "Escape":
			get_viewport().set_input_as_handled()
			run(C.close_dialog())
		return
	if key.is_empty():
		return
	var command: Variant = GcApp.keyboard_command(key, event.ctrl_pressed, event.meta_pressed,
			event.alt_pressed, event.shift_pressed, app.calc.mode, app.calc.base)
	if command != null:
		get_viewport().set_input_as_handled()
		run(command)


# ---------- window ----------

func _logical_size() -> Vector2:
	return Vector2(get_window().size) / ui_scale


func _remember_window() -> void:
	var window := get_window()
	var maximized := window.mode == Window.MODE_MAXIMIZED
	var logical := _logical_size()
	var previous := app.window
	app.dispatch(C.set_window({
		"width": previous["width"] if maximized else logical.x,
		"height": previous["height"] if maximized else logical.y,
		"maximized": maximized,
	}))
	if writer != null:
		writer.save(app.saved())


func _on_window_resized() -> void:
	if _closed:
		return
	var window := get_window()
	var maximized := window.mode == Window.MODE_MAXIMIZED
	var logical := _logical_size()
	var previous := app.window
	run(C.set_window({
		"width": previous["width"] if maximized else logical.x,
		"height": previous["height"] if maximized else logical.y,
		"maximized": maximized,
	}))


func _widen_for_scientific() -> void:
	var window := get_window()
	if window.mode == Window.MODE_MAXIMIZED:
		return
	var logical := _logical_size()
	if logical.x < 760.0:
		window.size = Vector2i(ceili(760.0 * ui_scale), window.size.y)


# ---------- theme ----------

func _is_dark() -> bool:
	match app.theme:
		GcAppState.ThemePref.DARK:
			return true
		GcAppState.ThemePref.LIGHT:
			return false
	return DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode()


func _apply_theme() -> void:
	var dark := _is_dark()
	theme = GcPalette.make_theme(dark)
	var bg: Color = GcPalette.tokens(dark)["bg"]
	_bg.color = bg
	RenderingServer.set_default_clear_color(bg)
	if _dialog != null:
		_dialog._built_for = "" # rebuild so theme-dependent buttons re-evaluate


func _on_system_theme_changed() -> void:
	# follows the OS live, but only while the preference is "Follow System"
	if app.theme == GcAppState.ThemePref.SYSTEM:
		_apply_theme.call_deferred()


# ---------- presentation ----------

func refresh() -> void:
	var calc := app.calc
	_keypad.rebuild(calc.mode)
	_keypad.refresh(app)
	_display.refresh(app)
	for pair in MODES:
		(_mode_buttons[pair[0]] as GcButton).set_variation(
				"ModeButtonActive" if calc.mode == pair[0] else "ModeButton")
	_history.visible = app.history_open
	if app.history_open:
		_history.refresh(app)
	_layout_workspace()
	_dialog.refresh(app)
	_set_underlay_locked(_dialog.is_open())
	_refresh_notice()
	_relayout()


func _relayout() -> void:
	var width := size.x
	var compact := width <= 420.0
	var padding := 12 if compact else 18
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, padding)
	_vbox.add_theme_constant_override("separation", 12 if compact else 16)
	_keypad.set_window_width(width)
	_display.set_window_width(width)
	var overlay := $Overlay as Control
	var holder := _menu_bar.get_parent() as Control
	overlay.offset_top = holder.size.y if holder.visible else 0.0
	_layout_notice()
	_dialog._layout()


func _layout_workspace() -> void:
	if _workspace == null:
		return
	var area := _workspace.size
	var narrow := size.x <= 700.0
	_calc_scroll.position = Vector2.ZERO
	if app.history_open and not narrow:
		var history_width := 265.0
		_calc_scroll.size = Vector2(maxf(area.x - history_width - 18.0, 0.0), area.y)
		_history.position = Vector2(area.x - history_width, 0.0)
		_history.size = Vector2(history_width, area.y)
		_history.z_index = 0
	else:
		_calc_scroll.size = area
		if app.history_open:
			var w := minf(300.0, area.x)
			_history.position = Vector2(area.x - w, 0.0)
			_history.size = Vector2(w, area.y)
			_history.z_index = 4
	_fit_calc_content()


func _fit_calc_content() -> void:
	# let the keypad grow to fill the column; scroll only when it cannot fit
	_calc_content.custom_minimum_size.y = maxf(_calc_scroll.size.y - 6.0, 0.0)


func _refresh_notice() -> void:
	var notice: Variant = app.notice
	_notice_panel.visible = notice != null
	if notice != null:
		_notice_label.text = notice
		_layout_notice()
		if notice == "Copied":
			_notice_timer.start()


func _layout_notice() -> void:
	if not _notice_panel.visible:
		return
	var area: Vector2 = ($Overlay as Control).size
	var width := minf(540.0, maxf(area.x - 48.0, 120.0))
	_notice_panel.size = Vector2(width, 0)
	_notice_panel.reset_size()
	_notice_panel.size.x = width
	_notice_panel.position = Vector2((area.x - width) * 0.5, area.y - 18.0 - _notice_panel.size.y)


func _on_notice_timeout() -> void:
	if app.notice == "Copied":
		run(C.dismiss_notice())


func _poll_writer_errors() -> void:
	if writer == null:
		return
	var message: Variant = writer.error()
	if message != null:
		push_error("Settings persistence failed")
		app.notice = message
		_refresh_notice()


## While a dialog is open Tab must stay inside it, so the controls beneath stop
## taking keyboard focus.
func _set_underlay_locked(locked: bool) -> void:
	if locked == _underlay_locked and not locked:
		return
	_underlay_locked = locked
	_lock_focus(_margin, locked)


func _lock_focus(node: Node, locked: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			child.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
		_lock_focus(child, locked)
