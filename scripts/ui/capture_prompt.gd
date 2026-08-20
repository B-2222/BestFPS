class_name CapturePrompt
extends CanvasLayer
## "Click to play" overlay, shown whenever the mouse is not captured.
##
## This is not decoration -- the browser build does not work without it.
## Pointer lock can only be requested from a user gesture, so the capture
## attempt in [PlayerInput]'s _ready() is refused on the web and the game sits
## there looking frozen: mouse look does nothing and [method
## PlayerInput.fill_command] deliberately returns empty input while the mouse is
## free. Telling the player to click is the whole fix.
##
## It earns its place on desktop too, as the thing you see after pressing Esc.

const CONTROLS := "WASD move     Space jump     Shift sprint     Ctrl crouch\n" \
		+ "sprint + crouch = slide     R respawn     F3 stats     Esc release mouse"

var _root: Control
var _shown: bool = true

func _ready() -> void:
	layer = 20
	_build()

func _process(_delta: float) -> void:
	# Polled rather than driven by a signal: mouse mode also changes from
	# outside the game (the browser dropping pointer lock on tab switch, the
	# window losing focus), and none of that routes through our input code.
	var want := Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
	if want != _shown:
		_shown = want
		_root.visible = want

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	# A centred container still has to be pulled back by half its own size.
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	column.add_child(_make_label("BestFPS", 44, Color(1, 1, 1)))
	column.add_child(_make_label("Milestone 1 — movement test", 16,
			Color(1.0, 0.78, 0.35)))
	column.add_child(_make_label("Click to play", 26, Color(0.85, 0.92, 1.0)))
	column.add_child(_make_label(CONTROLS, 14, Color(1, 1, 1, 0.62)))

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
