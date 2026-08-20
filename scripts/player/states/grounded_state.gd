class_name GroundedState
extends State
## On the floor: walking, sprinting, crouch-walking, and launching jumps.

var p: PlayerController

func _init(controller: PlayerController) -> void:
	id = &"grounded"
	p = controller

func enter(_from: StringName) -> void:
	# Kill residual downward velocity from the fall so floor snapping does not
	# have to fight it, and so the next jump starts from a known state.
	p.velocity.y = 0.0

func check_transitions(cmd: InputCommand) -> StringName:
	if not p.is_on_floor():
		return &"air"
	if p.config.slide_enabled and cmd.crouch_pressed \
			and p.slide_cooldown_left <= 0.0 \
			and p.get_horizontal_speed() >= p.config.slide_min_speed:
		return &"slide"
	return &""

func physics_update(cmd: InputCommand, delta: float) -> void:
	p.update_crouch(cmd)
	# Friction first, then acceleration -- Quake's order. At steady state the
	# acceleration exactly restores what friction removed, so holding a
	# direction still sits at target speed; release the keys and only friction
	# is left, so the stop is prompt. Reversing the order would make top speed
	# depend on the friction value, tangling two dials that need to stay
	# independent.
	p.apply_friction(delta)
	p.accelerate(p.wish_dir, p.get_target_speed(cmd), p.config.ground_accel, delta)

	if p.jump_buffer > 0.0 and p.try_jump():
		# Event-driven transition. Condition-driven ones belong in
		# check_transitions(); a jump is an event, and waiting a tick for
		# is_on_floor() to catch up would apply a tick of ground friction to a
		# player who is already in the air.
		p.machine.transition_to(&"air")
