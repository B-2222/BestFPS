class_name PlayerController
extends CharacterBody3D
## Resolves one [InputCommand] per physics tick into motion.
##
## Movement model is Quake/Source style -- accelerate toward a target speed
## along the wish direction, with separate ground friction -- rather than the
## [code]velocity.lerp(target)[/code] pattern most Godot tutorials use. The
## difference matters: lerping makes stopping distance proportional to current
## speed, so the character floats when fast and feels sticky when slow. Split
## acceleration and friction and you can tune "leaves the ground instantly"
## independently of "stops on a dime", which is the whole game of FPS feel.
##
## This node owns *physics*. View effects live in [CameraRig], device polling
## lives in [PlayerInput]. Nothing here reads the [Input] singleton.

signal jumped()
## Emitted on touchdown with the downward speed at impact, for the landing dip
## and (Milestone 6) landing sounds and fall damage.
signal landed(impact_speed: float)
## Emitted when the body is teleported up a stair, so the camera can smooth it.
signal stepped(height: float)
signal movement_state_changed(state_id: StringName)

const GroundedStateScript := preload("res://scripts/player/states/grounded_state.gd")
const AirStateScript := preload("res://scripts/player/states/air_state.gd")
const SlideStateScript := preload("res://scripts/player/states/slide_state.gd")

## Collision margin for the stair probes. Must stay small: see _step_up().
const STEP_MARGIN := 0.001
## Extra height probed above max_step_height so an exactly-limit-height step
## is still reachable rather than sitting on a knife edge.
const STEP_EPSILON := 0.005
## Collision margin for the stand-up headroom check.
const HEADROOM_MARGIN := 0.02
## Floor on the hull height, purely to keep a mis-tuned config from producing a
## zero-height collision shape.
const MIN_HULL_HEIGHT := 0.2

@export var config: PlayerConfig

## Node that fills the per-tick [InputCommand]. Resolved on ready unless
## something already called [method set_input_source] -- a bot spawner setting
## a brain immediately after instantiate() runs *before* _ready(), and silently
## losing that assignment would be a very quiet bug.
@export var input_source_path: NodePath = ^"PlayerInput"

@onready var collider: CollisionShape3D = $Collider
@onready var head: Node3D = $Head
## Authoritative aim origin. Never receives bob, dip or tilt -- see
## [CameraRig] for why weapons must not fire from the rendered camera.
@onready var aim_point: Marker3D = $Head/AimPoint

var machine: StateMachine
var cmd: InputCommand

## Horizontal unit vector the player is asking to move along, in world space.
var wish_dir: Vector3 = Vector3.ZERO
## 0..1 scale of how hard they are pushing (always 1 on keyboard, analog-ready).
var wish_scale: float = 0.0

var is_crouched: bool = false
var time_since_floor: float = 0.0
var jump_buffer: float = 0.0
var slide_cooldown_left: float = 0.0

var yaw: float = 0.0
var pitch: float = 0.0

## Accumulated stair pop the camera has not smoothed away yet.
var pending_step: float = 0.0

var _input_source: Node = null
var _input_source_assigned: bool = false
var _hull: CylinderShape3D
var _current_height: float = 1.8
var _current_eye: float = 1.62
var _was_on_floor: bool = false
var _spawn_transform: Transform3D

# ---------------------------------------------------------------------------

## The command buffer is built here rather than in _ready() so that anything
## holding a freshly instantiated player -- a test harness, a bot spawner --
## can write to it before the node enters the tree.
func _init() -> void:
	cmd = InputCommand.new()

func _ready() -> void:
	if config == null:
		config = load("res://assets/config/player_default.tres") as PlayerConfig
	if config == null:
		config = PlayerConfig.new()
		push_warning("PlayerController: no config assigned, using defaults.")

	# Duplicate the shape so two players (or a player and a bot) resizing
	# themselves for crouch do not fight over one shared resource.
	_hull = (collider.shape as CylinderShape3D).duplicate()
	collider.shape = _hull

	_spawn_transform = global_transform

	floor_max_angle = deg_to_rad(config.floor_max_angle_deg)
	floor_snap_length = config.floor_snap_length
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	slide_on_ceiling = true
	up_direction = Vector3.UP
	max_slides = 6
	safe_margin = 0.001

	_current_height = config.standing_height
	_current_eye = config.standing_eye_height
	_apply_height()

	if not _input_source_assigned:
		_input_source = get_node_or_null(input_source_path)

	machine = StateMachine.new()
	machine.add_state(GroundedStateScript.new(self))
	machine.add_state(AirStateScript.new(self))
	machine.add_state(SlideStateScript.new(self))
	machine.state_changed.connect(_on_state_changed)
	# Start airborne. If we spawned on the ground we land on tick one, which
	# is one clean code path instead of two.
	machine.start(&"air")

func _physics_process(delta: float) -> void:
	if _input_source != null:
		_input_source.fill_command(cmd, delta)
	cmd.tick += 1

	_was_on_floor = is_on_floor()
	if _was_on_floor:
		time_since_floor = 0.0
	else:
		time_since_floor += delta

	jump_buffer = maxf(jump_buffer - delta, 0.0)
	if cmd.jump_pressed or (config.auto_bhop and cmd.jump_held):
		jump_buffer = config.jump_buffer_time
	slide_cooldown_left = maxf(slide_cooldown_left - delta, 0.0)

	_update_wish_dir()

	machine.update(cmd, delta)

	_update_height(delta)
	_step_up(delta)

	var impact_speed := -velocity.y
	move_and_slide()

	if not _was_on_floor and is_on_floor() and impact_speed > 0.0:
		landed.emit(impact_speed)

	cmd.clear_one_shots()

# --- look ------------------------------------------------------------------

## Applied the instant a mouse event arrives, not on the physics tick, so aim
## latency is bounded by the display refresh rather than the tick rate.
func apply_look(mouse_delta: Vector2) -> void:
	yaw = wrapf(yaw - mouse_delta.x * config.mouse_sensitivity, -PI, PI)
	pitch = clampf(
		pitch - mouse_delta.y * config.mouse_sensitivity,
		deg_to_rad(config.pitch_min_deg),
		deg_to_rad(config.pitch_max_deg))
	rotation.y = yaw
	head.rotation.x = pitch
	cmd.yaw = yaw
	cmd.pitch = pitch

## World-space transform weapons should fire from. Explicitly not the camera:
## bob and recoil move the camera for feel, and if shots originated there the
## feel layer would silently change where bullets go.
func get_aim_transform() -> Transform3D:
	return aim_point.global_transform

# --- movement primitives (used by states) ----------------------------------

## Quake's PM_Accelerate. Only ever adds speed *along* [param dir], and only up
## to [param target_speed], so pushing sideways redirects rather than stacks.
func accelerate(dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	if dir == Vector3.ZERO or target_speed <= 0.0:
		return
	var current_speed := velocity.dot(dir)
	var add_speed := target_speed - current_speed
	if add_speed <= 0.0:
		return
	velocity += dir * minf(accel * target_speed * delta, add_speed)

## Quake's PM_AirAccelerate. Same shape, except the *target* is clamped to
## [member PlayerConfig.air_speed_cap] while the acceleration rate still scales
## with the full target speed. That asymmetry is what makes air strafing work.
func air_accelerate(dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	if dir == Vector3.ZERO or target_speed <= 0.0:
		return
	var capped := minf(target_speed, config.air_speed_cap)
	var current_speed := velocity.dot(dir)
	var add_speed := capped - current_speed
	if add_speed <= 0.0:
		return
	velocity += dir * minf(accel * target_speed * delta, add_speed)

func apply_friction(delta: float) -> void:
	apply_friction_value(config.friction, delta)

func apply_friction_value(friction: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxf(speed, config.stop_speed)
	var new_speed := maxf(speed - control * friction * delta, 0.0)
	# Named `retained` rather than `scale`, which would shadow Node3D.scale.
	var retained := new_speed / speed
	velocity.x *= retained
	velocity.z *= retained

func try_jump() -> bool:
	if jump_buffer <= 0.0:
		return false
	if not (is_on_floor() or time_since_floor <= config.coyote_time):
		return false
	jump_buffer = 0.0
	# Burn the coyote window so one press cannot become two jumps.
	time_since_floor = config.coyote_time + 1.0
	# maxf, not assignment: launching off a ramp should keep the ramp's boost.
	velocity.y = maxf(velocity.y, config.jump_velocity)
	jumped.emit()
	return true

## Target ground speed for the current command, before the wish scale.
func get_target_speed(cmd_in: InputCommand) -> float:
	var speed := config.walk_speed
	if is_crouched:
		speed = config.walk_speed * config.crouch_speed_mult
	elif cmd_in.sprint_held:
		if not config.sprint_forward_only or cmd_in.move_axis.y > 0.1:
			speed = config.sprint_speed
	return speed * wish_scale

func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func get_horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func set_horizontal_velocity(v: Vector3) -> void:
	velocity.x = v.x
	velocity.z = v.z

func get_state_id() -> StringName:
	return machine.current.id if machine != null and machine.current != null else &""

# --- crouch ----------------------------------------------------------------

## Hold-to-crouch, with a headroom check so you cannot stand up inside a vent.
func update_crouch(cmd_in: InputCommand) -> void:
	if cmd_in.crouch_held:
		is_crouched = true
	elif is_crouched and can_stand_up():
		is_crouched = false

## The crouched hull keeps its feet planted, so "is there room to stand?" is
## exactly "can the crouched hull sweep up by the height difference?".
##
## Uses an explicit margin for the same reason the stair probes do: at
## test_move()'s 0.08 m default the player would refuse to stand with 8 cm of
## clear air above their head. Small, but not zero -- standing up into a
## ceiling by a hair leaves the physics server to depenetrate the body, which
## reads as a lurch.
func can_stand_up() -> bool:
	var needed := config.standing_height - _current_height
	if needed <= 0.001:
		return true
	return not test_move(global_transform, Vector3.UP * needed, null, HEADROOM_MARGIN)

func _update_height(delta: float) -> void:
	var target_h := config.crouch_height if is_crouched else config.standing_height
	var target_eye := config.crouch_eye_height if is_crouched else config.standing_eye_height
	# Exponential smoothing: frame-rate independent, unlike a raw lerp weight.
	var t := 1.0 - exp(-delta / maxf(config.crouch_transition_time, 0.0001))
	_current_height = lerpf(_current_height, target_h, t)
	_current_eye = lerpf(_current_eye, target_eye, t)
	_apply_height()

func _apply_height() -> void:
	# Guard against a degenerate hull only. A cylinder has no height >= 2 *
	# radius rule (that constraint belongs to capsules), so crouch_height is
	# free to go below the hull diameter.
	_hull.height = maxf(_current_height, MIN_HULL_HEIGHT)
	# The hull is centre-anchored; keep the feet at the body origin so crouching
	# lowers the head instead of lifting the feet.
	collider.position.y = _hull.height * 0.5
	head.position.y = _current_eye

func get_current_height() -> float:
	return _current_height

# --- stairs ----------------------------------------------------------------

func _update_wish_dir() -> void:
	var b := global_transform.basis
	var dir := (b.x * cmd.move_axis.x) + (-b.z * cmd.move_axis.y)
	dir.y = 0.0
	var length := dir.length()
	if length < 0.001:
		wish_dir = Vector3.ZERO
		wish_scale = 0.0
		return
	wish_dir = dir / length
	wish_scale = minf(length, 1.0)

## Godot's CharacterBody3D does not climb stairs; without this, a 0.2 m ledge
## is a wall. The move is the standard up / forward / probe-down test: if a
## walkable surface sits within [member PlayerConfig.max_step_height] of our
## feet and the path there is clear, teleport the body up by exactly the
## surface height and let move_and_slide() carry it forward this same tick.
##
## Deliberately runs only while grounded. Doing it midair turns every ledge
## into a free mantle, which is a mechanic we have not decided to have.
func _step_up(delta: float) -> void:
	if not is_on_floor() or config.max_step_height <= 0.0:
		return
	var horizontal := get_horizontal_velocity()
	if horizontal.length_squared() < 0.01:
		return

	var motion := horizontal * delta
	var from := global_transform

	# Every probe below passes STEP_MARGIN explicitly. test_move() defaults to
	# a 0.08 m safety margin, which is enormous relative to a stair: clearing a
	# 0.35 m step by exactly 0 m reads as a collision at that margin and the
	# step is silently rejected. This cost an afternoon; do not remove it.
	if not test_move(from, motion, null, STEP_MARGIN):
		return  # Path already clear; nothing in the way to step over.

	# Rise a hair past the limit so a step of exactly max_step_height still has
	# air above it to move through.
	var step_up := config.max_step_height + STEP_EPSILON
	var up := Vector3.UP * step_up
	if test_move(from, up, null, STEP_MARGIN):
		return  # No headroom to rise: low ceiling, not a stair.

	var raised := from.translated(up)
	if test_move(raised, motion, null, STEP_MARGIN):
		return  # Still blocked up there: it is a wall, slide along it instead.

	var ahead := raised.translated(motion)
	var hit := KinematicCollision3D.new()
	if not test_move(ahead, Vector3.DOWN * (step_up + 0.05), hit, STEP_MARGIN):
		return  # Nothing underneath: a ledge to fall off, not a step to climb.

	if hit.get_normal(0).angle_to(Vector3.UP) > floor_max_angle:
		return  # Landing surface is too steep to stand on.

	# How far we fell short of dropping all the way back down is exactly the
	# height of the surface we found.
	var rise := step_up - absf(hit.get_travel().y)
	if rise <= 0.001:
		return  # Ground continues at the same level; nothing was climbed.

	global_position.y += rise + STEP_MARGIN
	# Capped: if no camera rig is attached to drain this, an uncapped
	# accumulator would hand a huge offset to whatever consumes it later.
	pending_step = minf(pending_step + rise, config.max_step_height * 3.0)
	stepped.emit(rise)

## Hand the accumulated stair pop to the camera, which owes us a smooth-out.
func consume_pending_step() -> float:
	var s := pending_step
	pending_step = 0.0
	return s

# --- misc ------------------------------------------------------------------

## Swap the source of commands. Milestone 3 passes a bot brain here; the smoke
## test passes null and writes to [member cmd] directly.
func set_input_source(node: Node) -> void:
	_input_source = node
	_input_source_assigned = true

## Return to the spawn point in a fully clean state.
##
## Resetting the view angles matters as much as the position: assigning
## global_transform moves the body, but `yaw` would still hold the old heading,
## and the next mouse movement would snap the camera back to where the player
## was looking before they respawned.
func respawn() -> void:
	velocity = Vector3.ZERO
	global_transform = _spawn_transform

	yaw = _spawn_transform.basis.get_euler().y
	pitch = 0.0
	rotation.y = yaw
	head.rotation.x = pitch
	cmd.yaw = yaw
	cmd.pitch = pitch

	# Clear anything in flight, or a jump buffered a moment before respawning
	# fires the instant the player reappears.
	jump_buffer = 0.0
	time_since_floor = 0.0
	slide_cooldown_left = 0.0
	pending_step = 0.0

	is_crouched = false
	_current_height = config.standing_height
	_current_eye = config.standing_eye_height
	_apply_height()
	machine.transition_to(&"air")

func _on_state_changed(_from: StringName, to: StringName) -> void:
	movement_state_changed.emit(to)
