class_name PlayerInput
extends Node
## Turns physical devices into an [InputCommand].
##
## The only place in the player that touches the [Input] singleton. Milestone 3
## swaps this node for a bot brain and Milestone 5 for a network receiver;
## because both produce the same struct, neither needs the movement code to
## change. See docs/architecture.md.

@export var controller_path: NodePath = ^".."

var _controller: PlayerController

func _ready() -> void:
	_controller = get_node(controller_path) as PlayerController
	# Headless (CI, smoke tests) has no window to capture the mouse into.
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and captured:
		# Applied immediately rather than deferred to the physics tick, so aim
		# latency tracks the display refresh instead of the 120 Hz simulation.
		_controller.apply_look((event as InputEventMouseMotion).relative)
		return

	if event.is_action_pressed(&"ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"respawn"):
		_controller.respawn()

## Called by [PlayerController] once per physics tick.
func fill_command(cmd: InputCommand, _delta: float) -> void:
	# With the mouse released the window is effectively unfocused; holding a
	# key down through an alt-tab should not walk the player into a wall.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		cmd.clear()
		return

	cmd.move_axis = Input.get_vector(
		&"move_left", &"move_right", &"move_back", &"move_forward")
	cmd.jump_pressed = Input.is_action_just_pressed(&"jump")
	cmd.jump_held = Input.is_action_pressed(&"jump")
	cmd.crouch_pressed = Input.is_action_just_pressed(&"crouch")
	cmd.crouch_held = Input.is_action_pressed(&"crouch")
	cmd.sprint_held = Input.is_action_pressed(&"sprint")
	cmd.yaw = _controller.yaw
	cmd.pitch = _controller.pitch
