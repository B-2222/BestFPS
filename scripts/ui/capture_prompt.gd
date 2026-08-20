class_name CapturePrompt
extends CanvasLayer
## A small hint, not a gate.
##
## The game is live and playable the moment the page finishes loading -- WASD
## works immediately (see [method PlayerInput.fill_command], which gates on
## window focus rather than mouse capture). The only thing a click adds is
## mouse look, because no browser will hand over pointer lock without a user
## gesture. So this says so quietly in a corner instead of blocking the view
## with a "click to play" wall.
##
## It hides itself the moment the mouse is actually captured, and shrinks to a
## single line once the player has clicked at all, so a browser that refuses
## pointer lock never leaves a permanent obstruction on screen.

## Seconds between checks. On the web each poll crosses into JavaScript, and
## nothing here needs to react within a single frame.
const POLL_INTERVAL := 0.2

const CONTROLS := "WASD move     Space jump     Shift sprint     Ctrl crouch (sprint + crouch = slide)" \
		+ "\nR respawn     F3 stats     Esc release mouse"

var _input_source: PlayerInput
var _card: PanelContainer
var _headline: Label
var _detail: Label
var _poll_timer: float = 0.0

func _ready() -> void:
	layer = 20
	_input_source = get_tree().get_first_node_in_group(&"player_input") as PlayerInput
	_build()
	_refresh()

func _process(delta: float) -> void:
	# Polled rather than driven by a signal: mouse mode also changes from
	# outside the game -- the browser dropping pointer lock on a tab switch, the
	# window losing focus -- and none of that routes through our input code.
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	_refresh()

func _refresh() -> void:
	if _input_source == null:
		_card.visible = false
		return

	if _input_source.is_mouse_captured():
		_card.visible = false
		return

	_card.visible = true
	if _input_source.capture_attempts == 0:
		_headline.text = "Click anywhere for mouse look"
		_detail.text = CONTROLS
		_detail.visible = true
	else:
		# They have already clicked and the browser did not grant pointer lock.
		# Shrink out of the way rather than nagging over the top of the game.
		_headline.text = "Mouse look unavailable — keyboard still works. Click again to retry."
		_detail.visible = false

func _build() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_bottom = -56
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)

	_headline = _make_label("", 20, Color(0.88, 0.94, 1.0))
	column.add_child(_headline)

	_detail = _make_label(CONTROLS, 13, Color(1, 1, 1, 0.62))
	column.add_child(_detail)

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
