class_name AirState
extends State
## Airborne: gravity, air control, and the coyote-time jump.

var p: PlayerController

func _init(controller: PlayerController) -> void:
	id = &"air"
	p = controller

func check_transitions(cmd: InputCommand) -> StringName:
	if not p.is_on_floor():
		return &""
	# Landing straight into a slide while holding crouch. This is the move that
	# makes drop-downs feel deliberate instead of punishing, and it is why
	# crouch_held (not crouch_pressed) is checked here.
	if p.config.slide_enabled and cmd.crouch_held \
			and p.slide_cooldown_left <= 0.0 \
			and p.get_horizontal_speed() >= p.config.slide_min_speed:
		return &"slide"
	return &"grounded"

func physics_update(cmd: InputCommand, delta: float) -> void:
	p.update_crouch(cmd)
	p.velocity.y = maxf(p.velocity.y - p.config.gravity * delta, -p.config.terminal_velocity)
	p.air_accelerate(p.wish_dir, p.get_target_speed(cmd), p.config.air_accel, delta)

	# Coyote jump: try_jump() owns the grace-window check.
	if p.jump_buffer > 0.0:
		p.try_jump()
