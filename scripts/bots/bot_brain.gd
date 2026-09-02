class_name BotBrain
extends Node
## Fills an [InputCommand] each tick, exactly as [PlayerInput] does.
##
## This is the whole reason input was made a value back in Milestone 1. A bot
## does not get a private movement path or a special way to shoot -- it presses
## the same buttons, through the same struct, into the same controller. Bots
## are therefore bound by every rule the player is: the same acceleration, the
## same jump height, the same weapon cooldowns, the same spread.
##
## It also means bots run correctly on a server that never renders them, which
## is what Milestone 5 needs.

@export var profile: BotProfile
## Weapon slot for this individual bot, or -1 to take the profile's. Set by
## [BotDirector] so a roster is a mixed bag rather than four copies of the same
## rifle -- difficulty is a tier, but what someone is carrying is not.
@export var weapon_slot_override: int = -1
@export var controller_path: NodePath = ^".."
@export var agent_path: NodePath = ^"../NavigationAgent3D"

## Volume this bot is allowed to walk in. Set by [BotDirector]: a duel-room bot
## gets its room, a free-roaming one gets the main arena.
##
## Confinement is on movement only, never on senses. A bot that stopped being
## able to *see* you the moment you stepped outside its box would let you shoot
## it from the doorway with impunity, which is a worse lie than a bot that
## wanders -- so it still fights back at anyone it can genuinely see, it just
## will not follow them out.
var bounds: AABB = AABB()
var is_confined: bool = false

var controller: PlayerController
var agent: NavigationAgent3D
var senses: BotSenses
var machine: StateMachine

## Shots taken since the current burst began; the engage state counts against it.
var shots_fired: int = 0
## Constant offset applied to aim, resampled between bursts.
var aim_error: Vector2 = Vector2.ZERO

## Counts down after a retreat. While it is running the bot will not retreat
## again, so a hurt bot backs off once and then commits instead of oscillating
## on the edge of its health threshold forever.
var fight_commit: float = 0.0

var _weapon_requested: bool = false
var _goal_set: bool = false

func _ready() -> void:
	add_to_group(&"bots")
	controller = get_node(controller_path) as PlayerController
	agent = get_node_or_null(agent_path) as NavigationAgent3D
	if profile == null:
		profile = load("res://assets/config/bots/normal.tres") as BotProfile
	if profile == null:
		profile = BotProfile.new()

## Build the senses and the state machine on the first tick rather than in
## [method _ready].
##
## _ready() runs children-first, so this node is ready *before* the
## PlayerController above it -- which means its @onready references (head,
## aim_point, weapons) are all still null here. Deferring to the first
## fill_command is safe because that call only ever comes from the controller's
## own _physics_process, which cannot run until the controller is ready.
func _ensure_initialised() -> void:
	if senses != null:
		return
	senses = BotSenses.new(controller, controller.head, profile)

	machine = StateMachine.new()
	machine.add_state(BotIdleState.new(self))
	machine.add_state(BotHuntState.new(self))
	machine.add_state(BotEngageState.new(self))
	machine.add_state(BotRetreatState.new(self))
	machine.start(&"bot_idle")

	if agent != null:
		agent.path_desired_distance = 0.7
		agent.target_desired_distance = 1.2

func _ensure_weapon_signal() -> void:
	if controller.weapons == null or controller.weapons.fired.is_connected(_on_fired):
		return
	controller.weapons.fired.connect(_on_fired)

func _on_fired(_weapon: WeaponResource) -> void:
	shots_fired += 1

## Called by [PlayerController] once per physics tick -- the same call
## [PlayerInput] answers.
func fill_command(cmd: InputCommand, delta: float) -> void:
	_ensure_initialised()
	_ensure_weapon_signal()
	# Cleared first, every tick. The command is a *value* that lives on the
	# controller between ticks, so a state that only ever sets fields it wants
	# never unsets the ones it does not: one shot fired leaves fire_held true
	# forever, and the bot keeps shooting through walls in every fight after
	# it. PlayerInput does not hit this because it writes every field from the
	# device each tick; a brain that only writes what it decided has to clear.
	# yaw, pitch and tick survive clear() by design.
	cmd.clear()
	if controller.is_dead:
		return
	if not _weapon_requested and controller.weapons != null:
		_weapon_requested = true
		cmd.weapon_slot = (weapon_slot_override if weapon_slot_override >= 0
				else profile.weapon_slot)

	fight_commit = maxf(fight_commit - delta, 0.0)
	senses.update(_enemies(), delta)

	# Out of its volume before the states get a say. Clamped goals and blocked
	# steps should make this unreachable, but "should" is doing a lot of work
	# in a system with physics pushes, respawns and geometry -- and a duel bot
	# that leaks into the corridor quietly ruins the fight next door rather
	# than failing loudly.
	if is_confined and not in_bounds(controller.global_position):
		_walk_home(cmd, delta)
	else:
		machine.update(cmd, delta)

	# Always, on both paths: the command carries the view angles the rest of the
	# tick reads, and walking home still turns the bot.
	cmd.yaw = controller.yaw
	cmd.pitch = controller.pitch

## Noise reaches bots through a group call rather than a subscription, so
## nothing making a sound needs to know bots exist.
##
## [param source] is whoever made it. A bot ignoring its own gunfire is not a
## nicety: without it a bot hears itself shoot, seeds a "last known position"
## on top of its own feet, and can never forget a target -- so memory never
## expires and it hunts a ghost between fights.
func hear_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	# A noise can arrive before the first tick, and a corpse does not listen.
	if senses == null or controller.is_dead or source == controller:
		return
	senses.hear(position, loudness)

## Head back inside, ignoring everything else until we are.
##
## Pathed rather than walked at directly. The nearest in-bounds point is
## usually straight through a wall -- a bot shoved into a sealed duel room is
## metres from its own arena with a building in between -- so walking at it
## just presses the bot into the masonry forever. The navigation mesh knows the
## way out of the door.
func _walk_home(cmd: InputCommand, delta: float) -> void:
	var home := clamp_to_bounds(controller.global_position)
	set_goal(home)
	if not follow_path(cmd):
		var offset := home - controller.global_position
		offset.y = 0.0
		if offset.length_squared() > 0.01:
			move_in_direction(offset.normalized(), cmd)
	aim_towards(home + Vector3.UP * 1.2, delta)

## Everyone this bot is willing to shoot at.
##
## Free-for-all for now: every player, plus every other bot. Teams arrive with
## the Milestone 5 lobby, and when they do the filter changes here and nowhere
## else -- the senses and the states only ever see the list this returns.
func _enemies() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group(&"player"):
		out.append(node)
	for other in get_tree().get_nodes_in_group(&"bots"):
		if other == self:
			continue
		var body: Node = (other as BotBrain).controller
		if body != null:
			out.append(body)
	return out

# --- helpers the states use -------------------------------------------------

func set_goal(position: Vector3) -> void:
	if agent == null:
		return
	position = clamp_to_bounds(position)
	# Always submit the first goal. NavigationAgent3D does not consider itself
	# to have a destination until target_position has actually been assigned,
	# so skipping the assignment because the default Vector3.ZERO happened to
	# be close enough leaves the agent permanently "finished" and the bot
	# standing still.
	if not _goal_set or agent.target_position.distance_to(position) > 0.6:
		_goal_set = true
		agent.target_position = position

## Walk the current path. Returns true while still travelling.
func follow_path(cmd: InputCommand) -> bool:
	if agent == null or agent.is_navigation_finished():
		return false
	var next := agent.get_next_path_position()
	var offset := next - controller.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0025:
		return true
	move_in_direction(offset.normalized(), cmd)
	return true

## Convert a world direction into the local stick input the controller expects.
## Bots steer by pressing movement keys, not by having their velocity set.
func move_in_direction(world_direction: Vector3, cmd: InputCommand) -> void:
	var local := controller.global_transform.basis.inverse() * world_direction
	cmd.move_axis = Vector2(local.x, -local.z).limit_length(1.0)

## Swing the view toward a point, capped by the profile's turn speed so a bot
## cannot instantly snap onto someone who appeared behind it.
##
## Returns the angle still left to travel, in radians, measured against the
## error-offset aim point rather than the true one. That distinction is what
## lets the engage state hold fire until its swing has landed without the gate
## having to know how big the profile's aim error is: a bot with sloppy aim
## still finishes its turn, it just finishes it slightly off target.
func aim_towards(point: Vector3, delta: float) -> float:
	var eye := controller.aim_point.global_position
	var offset := point - eye
	if offset.length_squared() < 0.0001:
		return 0.0
	var desired_yaw := atan2(-offset.x, -offset.z) + aim_error.x
	var desired_pitch := clampf(
		atan2(offset.y, Vector2(offset.x, offset.z).length()) + aim_error.y,
		deg_to_rad(controller.config.pitch_min_deg),
		deg_to_rad(controller.config.pitch_max_deg))
	var yaw_error := wrapf(desired_yaw - controller.yaw, -PI, PI)
	var pitch_error := desired_pitch - controller.pitch
	var step := profile.aim_speed * delta
	controller.yaw = _approach_angle(controller.yaw, desired_yaw, step)
	controller.pitch = clampf(
		controller.pitch + clampf(pitch_error, -step, step),
		deg_to_rad(controller.config.pitch_min_deg),
		deg_to_rad(controller.config.pitch_max_deg))
	controller.apply_view()
	return maxf(absf(yaw_error), absf(pitch_error))

## Resample the aim offset. Called between bursts rather than every frame: a
## per-frame jitter averages out to perfect aim over a burst, which is the
## opposite of what an error model should do.
func resample_aim_error(target_speed: float) -> void:
	var moving := clampf(target_speed / 9.0, 0.0, 1.0)
	var spread := deg_to_rad(profile.aim_error_degrees + profile.aim_error_moving * moving)
	aim_error = Vector2(randf_range(-spread, spread), randf_range(-spread, spread) * 0.55)

## A navigable point roughly [param distance] away in [param direction].
func nav_point_towards(direction: Vector3, distance: float) -> Vector3:
	var wanted := clamp_to_bounds(
			controller.global_position + direction.normalized() * distance)
	if agent == null:
		return wanted
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), wanted)

## Pull a point inside the bot's allowed volume, with a margin so a clamped
## goal never lands exactly on a wall the agent then refuses to path to.
func clamp_to_bounds(point: Vector3) -> Vector3:
	if not is_confined:
		return point
	var margin := 0.8
	var low := bounds.position + Vector3(margin, 0.0, margin)
	var high := bounds.end - Vector3(margin, 0.0, margin)
	return Vector3(clampf(point.x, low.x, high.x), point.y,
			clampf(point.z, low.z, high.z))

## Whether [param point] is somewhere this bot may stand.
func in_bounds(point: Vector3) -> bool:
	if not is_confined:
		return true
	return point.x >= bounds.position.x and point.x <= bounds.end.x \
			and point.z >= bounds.position.z and point.z <= bounds.end.z

## Whether the bot could walk [param distance] along [param direction] and
## still be standing on the navigation mesh.
##
## Used instead of pathfinding while fighting: recomputing a path every time a
## bot changes strafe direction is both expensive and laggy, and all combat
## footwork actually needs to know is "is there floor that way". It is also the
## only thing stopping a strafing bot from walking off the gap walkway.
func can_step_towards(direction: Vector3, distance: float) -> bool:
	if agent == null:
		return in_bounds(controller.global_position
				+ direction.normalized() * distance)
	var wanted := controller.global_position + direction.normalized() * distance
	if not in_bounds(wanted):
		return false
	var closest := NavigationServer3D.map_get_closest_point(
			agent.get_navigation_map(), wanted)
	# Compared flat: the closest navigable point under a bot standing on a
	# ledge is directly below it, and a vertical miss is not a blocked step.
	return Vector2(closest.x - wanted.x, closest.z - wanted.z).length() < 0.75

## Top up while nothing is in sight.
##
## Only the engage and retreat states used to reload, which meant a bot that
## broke off a fight with two rounds left walked into the next one with two
## rounds left. Reloading out of contact is the first habit a player picks up,
## and a bot that does not have it is not harder to fight, just erratic.
func reload_if_out_of_contact(cmd: InputCommand) -> void:
	var rt := weapon()
	if rt == null or senses.visible_target != null:
		return
	if rt.can_reload():
		cmd.reload_pressed = true

## The equipped weapon, or null before the loadout has been built.
func weapon() -> WeaponRuntime:
	if controller.weapons == null:
		return null
	return controller.weapons.current()

## Distance to whatever the bot is currently interested in, flat.
func distance_to_mark() -> float:
	if not senses.has_last_known:
		return INF
	var offset := senses.last_known_position - controller.global_position
	return Vector2(offset.x, offset.z).length()

static func _approach_angle(current: float, target: float, max_step: float) -> float:
	var difference := wrapf(target - current, -PI, PI)
	return wrapf(current + clampf(difference, -max_step, max_step), -PI, PI)
