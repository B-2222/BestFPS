class_name CameraRig
extends Node3D
## Everything that moves the camera for *feel* rather than for simulation.
##
## Sits below the aim pivot, so bob, dip, tilt and (Milestone 2) recoil kick
## compose additively onto the rendered view while
## [method PlayerController.get_aim_transform] stays clean. That separation is
## not cosmetic: if weapons fired from the rendered camera, tuning the head bob
## would silently change where bullets land, and hit registration bugs of that
## shape are miserable to find months later.
##
## Runs in _process, not _physics_process. View effects should be smooth at the
## display refresh rate, not quantised to the 120 Hz simulation.

## Fixed substep for the landing spring, so its response does not vary with
## frame rate.
const SPRING_TIMESTEP := 1.0 / 240.0
## Cap on how much spring time a single long frame may catch up, so a hitch or
## a breakpoint does not spend thousands of substeps.
const MAX_SPRING_CATCHUP := 0.25

@onready var camera: Camera3D = $Camera3D

var _controller: PlayerController
var _config: PlayerConfig

var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _land_offset: float = 0.0
var _land_velocity: float = 0.0
var _step_smooth: float = 0.0
var _roll: float = 0.0
var _tilt: float = 0.0
var _fov: float = 90.0

func _ready() -> void:
	_controller = _find_controller()
	if _controller == null:
		push_error("CameraRig: no PlayerController ancestor found.")
		set_process(false)
		return
	_controller.landed.connect(_on_landed)
	# Config is deliberately not read here. Godot readies children before their
	# parents, so PlayerController._ready() -- which resolves the fallback
	# config -- has not run yet. Picked up on the first frame instead.

func _find_controller() -> PlayerController:
	var node := get_parent()
	while node != null:
		if node is PlayerController:
			return node
		node = node.get_parent()
	return null

func _process(delta: float) -> void:
	if _config == null:
		_config = _controller.config
		if _config == null:
			return
		_fov = _config.view_fov_base
		camera.fov = _fov

	var speed := _controller.get_horizontal_speed()
	var grounded := _controller.is_on_floor()
	var sliding := _controller.get_state_id() == &"slide"

	var offset := Vector3.ZERO
	_roll = 0.0

	_update_bob(speed, grounded and not sliding, delta)
	offset += _apply_bob(speed)

	_update_landing(delta)
	offset.y -= _land_offset

	_update_step_smoothing(delta)
	offset.y -= _step_smooth

	_update_tilt(sliding, delta)
	_update_fov(speed, sliding, delta)

	position = offset
	rotation.z = _roll
	camera.fov = _fov

# --- bob -------------------------------------------------------------------

func _update_bob(speed: float, active: bool, delta: float) -> void:
	if not _config.view_bob_enabled:
		_bob_weight = 0.0
		return
	# Phase advances with distance travelled, not time, so the cadence stays
	# locked to the stride at every speed and stops dead when the player does.
	_bob_phase += speed * delta * _config.view_bob_frequency
	# Blend the whole effect out midair rather than freezing it, so leaving the
	# ground mid-stride does not lock a visible offset into the camera.
	var target := 1.0 if active else 0.0
	_bob_weight = lerpf(_bob_weight, target, 1.0 - exp(-delta * 10.0))

## Returns the positional component and adds its own roll contribution to
## [member _roll], which every layer in this file accumulates into.
func _apply_bob(speed: float) -> Vector3:
	if _bob_weight < 0.001:
		return Vector3.ZERO
	var amplitude := clampf(speed / maxf(_config.walk_speed, 0.001), 0.0, 1.4) * _bob_weight
	var phase := _bob_phase * TAU
	# Vertical at full rate, lateral at half: one dip per footfall, one sway per
	# stride. That 2:1 ratio traces a figure-eight, which is what reads as
	# walking rather than as a sine wave.
	var offset := Vector3(
		sin(phase * 0.5) * _config.view_bob_amount_h * amplitude,
		sin(phase) * _config.view_bob_amount_v * amplitude,
		0.0)
	_roll += sin(phase * 0.5) * deg_to_rad(_config.view_bob_roll_deg) * amplitude
	return offset

# --- landing ---------------------------------------------------------------

func _on_landed(impact_speed: float) -> void:
	# The player can land before our first _process runs, and the config is
	# resolved there (children are readied before parents). A landing we cannot
	# scale yet is simply one we skip.
	if _config == null:
		return
	_land_velocity += impact_speed * _config.view_land_dip_scale * 60.0

## Damped spring rather than a tween: impulses from successive landings add up
## naturally, and the return is asymmetric (fast down, settling up) the way real
## weight is.
##
## Integrated at a fixed substep rather than straight off the render frame. An
## explicit spring's response depends on its step size, and stepping it per
## frame made the same landing dip about 20% deeper at 144 fps than at 60 --
## a feel bug that only ever shows up on someone else's machine.
func _update_landing(delta: float) -> void:
	var remaining := minf(delta, MAX_SPRING_CATCHUP)
	while remaining > 0.0:
		var step := minf(remaining, SPRING_TIMESTEP)
		var acceleration := -_config.view_land_dip_stiffness * _land_offset \
				- _config.view_land_dip_damping * _land_velocity
		_land_velocity += acceleration * step
		_land_offset = clampf(_land_offset + _land_velocity * step,
				-_config.view_land_dip_max, _config.view_land_dip_max)
		remaining -= step

# --- stairs ----------------------------------------------------------------

func _update_step_smoothing(delta: float) -> void:
	# The controller teleports the body up each stair. Absorb the pop here and
	# pay it back over ~100 ms; without this every staircase strobes.
	_step_smooth += _controller.consume_pending_step()
	_step_smooth *= exp(-delta / maxf(_config.view_step_smooth_time, 0.001))
	if absf(_step_smooth) < 0.0005:
		_step_smooth = 0.0

# --- tilt and fov ----------------------------------------------------------

func _update_tilt(sliding: bool, delta: float) -> void:
	# Leaning into the strafe. Smoothed rather than snapped, because the tilt
	# arriving after the movement is what makes it read as body weight.
	var tilt_deg := _config.view_slide_tilt_deg if sliding else _config.view_strafe_tilt_deg
	var target := -_controller.cmd.move_axis.x * deg_to_rad(tilt_deg)
	_tilt = lerpf(_tilt, target, 1.0 - exp(-delta * _config.view_strafe_tilt_speed))
	_roll += _tilt

func _update_fov(speed: float, sliding: bool, delta: float) -> void:
	var target := _config.view_fov_base
	var span := maxf(_config.view_fov_speed_ref - _config.walk_speed, 0.001)
	target += _config.view_fov_speed_add * clampf((speed - _config.walk_speed) / span, 0.0, 1.0)
	if sliding:
		target += _config.view_fov_slide_add
	# Aiming pulls the FOV in. Subtracted last so it wins over the speed
	# bonus -- otherwise sprinting while aiming would widen the sight picture,
	# which is the opposite of what the player asked for.
	if _controller.is_aiming:
		target -= _controller.aim_fov_reduction
	_fov = lerpf(_fov, target, 1.0 - exp(-delta * _config.view_fov_blend))
