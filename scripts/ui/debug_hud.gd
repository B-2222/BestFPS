class_name DebugHud
extends CanvasLayer
## Tuning instrumentation for Milestone 1.
##
## Feel is subjective, but it is not unmeasurable. Being able to see the speed
## curve while you play is the difference between "acceleration feels off" and
## "ground_accel overshoots then friction claws it back". Toggle with F3.
##
## Built in code rather than as a .tscn: it is developer furniture, it will be
## deleted or hidden long before shipping, and a scene file full of anchor
## presets would be harder to read than this.

const GRAPH_SECONDS := 3.0
const GRAPH_SAMPLES := 180

var player: PlayerController

var _panel: PanelContainer
var _rows: Dictionary = {}
var _graph: SpeedGraph
var _hint: Label
var _peak_speed: float = 0.0
var _jump_count: int = 0

func _ready() -> void:
	layer = 10
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	_build_ui()
	if player == null:
		push_warning("DebugHud: no node in group 'player'.")
		return
	player.jumped.connect(func() -> void:
		_jump_count += 1
		_set_row("jumps", str(_jump_count)))
	player.landed.connect(func(speed: float) -> void:
		_set_row("last impact", "%.1f m/s" % speed))
	player.stepped.connect(func(height: float) -> void:
		_set_row("last step", "%.2f m" % height))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_panel.visible = not _panel.visible
		_hint.visible = _panel.visible

func _process(_delta: float) -> void:
	if player == null or not _panel.visible:
		return
	var speed := player.get_horizontal_speed()
	_peak_speed = maxf(_peak_speed, speed)

	_set_row("fps", str(Engine.get_frames_per_second()))
	_set_row("state", String(player.get_state_id()))
	_set_row("speed", "%.2f m/s" % speed)
	_set_row("peak", "%.2f m/s" % _peak_speed)
	_set_row("vertical", "%+.2f m/s" % player.velocity.y)
	_set_row("grounded", "yes" if player.is_on_floor() else "no")
	_set_row("crouched", "yes" if player.is_crouched else "no")
	_set_row("height", "%.2f m" % player.get_current_height())
	_set_row("position", "%.1f, %.1f, %.1f" % [
		player.global_position.x, player.global_position.y, player.global_position.z])

	_set_row("slide [F1]", "ON" if player.config.slide_enabled else "off")
	_set_row("auto-bhop [F2]", "ON" if player.config.auto_bhop else "off")

	_graph.push_sample(speed, player.config.sprint_speed)

# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "MOVEMENT  [F3]"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	column.add_child(title)

	for key in ["fps", "state", "speed", "peak", "vertical", "grounded",
			"crouched", "height", "jumps", "last impact", "last step", "position",
			"slide [F1]", "auto-bhop [F2]"]:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = key
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
		name_label.custom_minimum_size = Vector2(96, 0)
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.text = "-"
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
		row.add_child(value_label)

		column.add_child(row)
		_rows[key] = value_label

	# Inside the panel rather than at a hardcoded offset below it: adding a row
	# to the list above would otherwise silently overlap the graph.
	_graph = SpeedGraph.new()
	_graph.custom_minimum_size = Vector2(220, 68)
	column.add_child(_graph)

	_hint = Label.new()
	_hint.text = "WASD move   Space jump   Shift sprint   Ctrl crouch (sprint+crouch = slide)   R respawn   Esc free mouse"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -30
	_hint.offset_bottom = -10
	add_child(_hint)

func _set_row(key: String, value: String) -> void:
	var label: Label = _rows.get(key)
	if label != null:
		label.text = value

# ---------------------------------------------------------------------------

## Rolling speed history. The shape of the curve is the tuning signal: a sharp
## rise then a plateau means acceleration is right; a slow ramp means
## ground_accel is too low; a spike that sags means friction is fighting it.
class SpeedGraph:
	extends Control

	var _samples: PackedFloat32Array = PackedFloat32Array()
	var _reference: float = 10.0

	func _init() -> void:
		_samples.resize(DebugHud.GRAPH_SAMPLES)
		_samples.fill(0.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func push_sample(value: float, reference: float) -> void:
		_reference = maxf(reference, 0.001)
		for i in _samples.size() - 1:
			_samples[i] = _samples[i + 1]
		_samples[_samples.size() - 1] = value
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.05, 0.06, 0.08, 0.78), true)

		# Reference line at sprint speed, so you can see at a glance whether
		# the player is above or below their nominal top speed.
		var scale_max := _reference * 1.6
		var y_ref := size.y - (_reference / scale_max) * size.y
		draw_line(Vector2(0, y_ref), Vector2(size.x, y_ref), Color(1, 0.78, 0.35, 0.4), 1.0)

		var points := PackedVector2Array()
		for i in _samples.size():
			var x := (float(i) / float(_samples.size() - 1)) * size.x
			var y := size.y - clampf(_samples[i] / scale_max, 0.0, 1.0) * size.y
			points.append(Vector2(x, y))
		if points.size() > 1:
			draw_polyline(points, Color(0.45, 0.85, 1.0), 1.5, true)
