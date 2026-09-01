class_name SettingsMenu
extends CanvasLayer
## Key rebinding and mouse sensitivity, opened with Escape.
##
## Runs with PROCESS_MODE_ALWAYS and pauses the tree, which is what lets it own
## Escape while it is open: the player's input node is pausable, so it stops
## receiving events the moment the menu appears and cannot fight the menu for
## the same key.

const LISTEN_LABEL := "press a key…"

var _root: Control
var _rows: Dictionary = {}
var _sensitivity_value: Label
var _listening_action: StringName = &""
var _listening_button: Button
## Looked up by path: the headless test suites run a custom SceneTree, which
## does not create autoloads, and the menu must not take the level down with it.
var _settings: Node

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"settings_menu")
	_settings = get_node_or_null(^"/root/GameSettings")
	if _settings == null:
		set_process_input(false)
		return
	_build()
	_root.visible = false
	_settings.binding_changed.connect(_refresh_binding)

func is_open() -> bool:
	return _root != null and _root.visible

func toggle() -> void:
	if _root == null:
		return
	if is_open():
		close()
	else:
		open()

func open() -> void:
	if _root == null:
		return
	_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_all()

func close() -> void:
	if _root == null:
		return
	_cancel_listening()
	_root.visible = false
	get_tree().paused = false
	# Deliberately not recapturing the mouse here. On the web pointer lock has
	# to come from a user gesture, and closing a menu with the keyboard is not
	# one -- the player's next click takes it back.

func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return

	if _listening_action != &"":
		# Escape cancels rather than binding itself; a player who bound Escape
		# to something would have no way back out of this menu.
		if event is InputEventKey and (event as InputEventKey).pressed \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_listening()
			get_viewport().set_input_as_handled()
			return
		if _settings.is_bindable(event):
			_settings.rebind(_listening_action, event)
			_cancel_listening()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _begin_listening(action: StringName, button: Button) -> void:
	_cancel_listening()
	_listening_action = action
	_listening_button = button
	button.text = LISTEN_LABEL

func _cancel_listening() -> void:
	if _listening_button != null and is_instance_valid(_listening_button):
		_listening_button.text = _settings.describe(_listening_action)
	_listening_action = &""
	_listening_button = null

func _refresh_binding(action: StringName) -> void:
	if _rows.has(action):
		(_rows[action] as Button).text = _settings.describe(action)

func _refresh_all() -> void:
	for action in _rows:
		_refresh_binding(action)
	_sensitivity_value.text = "%.2fx" % _settings.mouse_sensitivity_scale

# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.12)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	column.add_child(title)

	column.add_child(_build_slider_row("Master volume", 0.0, 1.0, 0.05,
			_settings.master_volume,
			func(v: float) -> void: _settings.set_master_volume(v),
			func() -> float: return _settings.master_volume,
			"%d%%"))
	column.add_child(_build_sensitivity_row())
	column.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Click a binding, then press the key or mouse button you want."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for entry in _settings.REBINDABLE:
		list.add_child(_build_binding_row(entry[0], entry[1]))

	column.add_child(HSeparator.new())
	column.add_child(_build_buttons())

## Generic labelled slider, so volume and sensitivity stay one implementation.
func _build_slider_row(label_text: String, minimum: float, maximum: float,
		step: float, value: float, on_change: Callable, read_back: Callable,
		format: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(52, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 14)
	readout.text = format % (read_back.call() * 100.0)
	row.add_child(readout)

	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		readout.text = format % (v * 100.0))
	return row

func _build_sensitivity_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = "Mouse sensitivity"
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = _settings.mouse_sensitivity_scale
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		_settings.set_sensitivity_scale(value)
		_sensitivity_value.text = "%.2fx" % value)
	row.add_child(slider)

	_sensitivity_value = Label.new()
	_sensitivity_value.text = "%.2fx" % _settings.mouse_sensitivity_scale
	_sensitivity_value.custom_minimum_size = Vector2(52, 0)
	_sensitivity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sensitivity_value.add_theme_font_size_override("font_size", 14)
	row.add_child(_sensitivity_value)
	return row

func _build_binding_row(action: StringName, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var button := Button.new()
	button.text = _settings.describe(action)
	button.custom_minimum_size = Vector2(190, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _begin_listening(action, button))
	row.add_child(button)

	_rows[action] = button
	return row

func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END

	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(150, 34)
	reset.pressed.connect(func() -> void:
		_settings.reset_all()
		_refresh_all())
	row.add_child(reset)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(110, 34)
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row
