class_name SlideState
extends State
## Committed low-friction slide.
##
## The design intent is that a slide is a *decision*: it costs you turning
## authority and standing height for a burst of speed and a lower profile. So
## steering only redirects existing speed (it never adds any) and the slide
## ends on its own terms rather than being cancellable for free.

var p: PlayerController

var _elapsed: float = 0.0

func _init(controller: PlayerController) -> void:
	id = &"slide"
	p = controller

func enter(_from: StringName) -> void:
	_elapsed = 0.0
	p.is_crouched = true

	var horizontal := p.get_horizontal_velocity()
	var dir := horizontal.normalized() if horizontal.length_squared() > 0.001 \
			else -p.global_transform.basis.z
	var speed := minf(horizontal.length() + p.config.slide_boost, p.config.slide_max_speed)
	p.set_horizontal_velocity(dir * speed)
	p.velocity.y = minf(p.velocity.y, 0.0)

func exit(_to: StringName) -> void:
	p.slide_cooldown_left = p.config.slide_cooldown

func check_transitions(cmd: InputCommand) -> StringName:
	if not p.is_on_floor():
		return &"air"
	if _elapsed >= p.config.slide_max_time:
		return &"grounded"
	if p.get_horizontal_speed() < p.config.slide_min_exit_speed:
		return &"grounded"
	# Releasing crouch ends the slide, but only if there is room to stand.
	if not cmd.crouch_held and p.can_stand_up():
		return &"grounded"
	return &""

func physics_update(cmd: InputCommand, delta: float) -> void:
	_elapsed += delta

	# Gravity projected onto the floor plane. Zero on flat ground, downhill on
	# a slope, uphill-opposing when climbing -- one expression covers all three
	# and makes elevation worth reading on a map.
	var n := p.get_floor_normal()
	var down_slope := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	p.velocity += down_slope * p.config.gravity * p.config.slide_slope_boost * delta

	p.apply_friction_value(p.config.slide_friction, delta)

	_steer(delta)

	var horizontal := p.get_horizontal_velocity()
	if horizontal.length() > p.config.slide_max_speed:
		p.set_horizontal_velocity(horizontal.normalized() * p.config.slide_max_speed)

	if p.jump_buffer > 0.0 and p.try_jump():
		# Slide-hop: vertical launch, horizontal speed untouched. This is the
		# payoff for chaining slides and the reason slide has a cooldown.
		p.machine.transition_to(&"air")

## Rotate the velocity vector toward the wish direction without changing its
## length, so steering trades heading for nothing and cannot be used to
## accelerate out of the slide's speed budget.
func _steer(delta: float) -> void:
	if p.wish_dir == Vector3.ZERO:
		return
	var horizontal := p.get_horizontal_velocity()
	var speed := horizontal.length()
	if speed < 0.001:
		return
	var current_dir := horizontal / speed
	# slerp is undefined for opposed vectors; a 180 degree flip is not steering
	# anyway, it is a stop request, which check_transitions already handles.
	if current_dir.dot(p.wish_dir) < -0.99:
		return
	var new_dir := current_dir.slerp(p.wish_dir, clampf(p.config.slide_steer * delta, 0.0, 1.0))
	p.set_horizontal_velocity(new_dir.normalized() * speed)
