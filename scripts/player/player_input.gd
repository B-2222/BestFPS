class_name PlayerInput
extends Node
## Turns physical devices into an [InputCommand].
##
## The only place in the player that touches the [Input] singleton. Milestone 3
## swaps this node for a bot brain and Milestone 5 for a network receiver;
## because both produce the same struct, neither needs the movement code to
## change. See docs/architecture.md.

@export var controller_path: NodePath = ^".."

## True once anything has asked for the mouse, whether or not it was granted.
## [CapturePrompt] uses it to stop showing the full-screen prompt to someone who
## has already clicked.
var capture_attempts: int = 0

var _controller: PlayerController
var _is_web: bool = false

## Set when we take the mouse, cleared by the next motion event.
## See [method _input] for why.
var _discard_next_motion: bool = false

func _ready() -> void:
	_controller = get_node(controller_path) as PlayerController
	_is_web = OS.has_feature("web")

	# Capture the mouse on start on desktop only.
	#
	# Headless (CI, smoke tests) has no window to capture into. The browser is
	# the subtler case: it refuses pointer lock outside a user gesture, but
	# Godot's mouse mode still reports whatever we *asked* for -- so requesting
	# capture here would make the game report itself as captured when the mouse
	# is still free. On web the first click or keypress does it instead.
	if DisplayServer.get_name() != "headless" and not _is_web:
		_capture_mouse()

## Whether the mouse is *actually* captured.
##
## On the web this asks the DOM rather than Godot. Godot reports the mouse mode
## it last asked for, and a browser is free to refuse pointer lock -- some will
## only grant it from a listener running synchronously inside the real event,
## which is not how the engine dispatches input. Trusting Godot's answer there
## makes the game believe it has the mouse when it does not.
func is_mouse_captured() -> bool:
	if _is_web:
		return bool(JavaScriptBridge.eval("!!document.pointerLockElement", true))
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

## Uses _input rather than _unhandled_input so no Control in the HUD can quietly
## swallow the click that starts the game.
func _input(event: InputEvent) -> void:
	var captured := is_mouse_captured()

	if event is InputEventMouseMotion:
		if not captured:
			return
		# Browsers deliver one large movementX/movementY immediately after
		# pointer lock is granted -- the jump from wherever the cursor was to
		# the lock origin. Fed straight into apply_look() that spins the view
		# to the sky on the first click. Drop exactly one event; a real flick
		# never depends on the single frame after capture.
		if _discard_next_motion:
			_discard_next_motion = false
			return
		# Applied immediately rather than deferred to the physics tick, so aim
		# latency tracks the display refresh instead of the 120 Hz simulation.
		_controller.apply_look((event as InputEventMouseMotion).relative)
		return

	if event.is_action_pressed(&"ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"respawn"):
		_controller.respawn()
		return

	# Live toggles for the two Milestone 1 questions that are about the game's
	# identity rather than tuning. They live on the config Resource, which
	# normally means opening the editor -- and the browser build has no editor,
	# so without these the questions cannot be answered by the person whose
	# call it is. Runtime only; nothing is saved.
	if event.is_action_pressed(&"toggle_slide"):
		_controller.config.slide_enabled = not _controller.config.slide_enabled
		return
	if event.is_action_pressed(&"toggle_bhop"):
		_controller.config.auto_bhop = not _controller.config.auto_bhop
		return

	if captured:
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_capture_mouse()
		get_viewport().set_input_as_handled()
		return

	# Any key also takes the mouse. Belt and braces: if a browser refuses the
	# click-driven lock, pressing W still starts the game rather than leaving
	# the player staring at a prompt that does nothing. Deliberately not marked
	# handled, so the same keypress still moves them.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		if key.keycode != KEY_ESCAPE and key.physical_keycode != KEY_ESCAPE:
			_capture_mouse()

func _capture_mouse() -> void:
	capture_attempts += 1
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_discard_next_motion = true

## Called by [PlayerController] once per physics tick.
func fill_command(cmd: InputCommand, _delta: float) -> void:
	# Gated on window focus, NOT on mouse capture. Those came apart on the web:
	# if the browser refuses pointer lock, gating movement on capture leaves the
	# player unable to do anything at all, which reads as a broken game. Losing
	# mouse look is a degraded experience; losing WASD is no experience.
	if not _window_has_focus():
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

func _window_has_focus() -> bool:
	# Headless has no window. On the web the browser only delivers key events to
	# a focused document anyway, and Godot's focus tracking there is less
	# reliable than the browser's own -- so do not second-guess it.
	if DisplayServer.get_name() == "headless" or _is_web:
		return true
	var window := get_window()
	return window == null or window.has_focus()
