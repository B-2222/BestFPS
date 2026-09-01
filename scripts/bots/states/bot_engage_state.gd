class_name BotEngageState
extends State
## A target has been in view for longer than the reaction time. Fight it.
##
## Three jobs, kept visibly separate below: point the gun, move the feet, work
## the trigger. They are separate because they fail separately -- a bot that
## shoots too well is a different tuning problem to a bot that walks into a
## wall -- and because the trigger logic is the part that has to stay honest.
##
## The bot fires by setting the same [InputCommand] fields a player's mouse
## sets. It has no path to [WeaponController] that the player does not have, so
## it cannot fire faster than the weapon allows, cannot ignore spread, and
## cannot shoot while reloading.

## How long after losing sight the bot keeps fighting rather than switching to
## a hunt. Without it, a target crossing behind a pillar for three ticks resets
## the whole engagement, and the bot reacquires from scratch every time -- which
## reads as an enemy that forgets you mid-fight.
const LOST_CONTACT_GRACE := 0.45

## Aim at the chest. Aiming at the origin means aiming at the feet, and a bot
## that shoots people in the shins is not missing -- it is doing 80% damage on
## every hit, which quietly doubles time-to-kill.
const AIM_HEIGHT := 1.2

## The swing has to land within this before the bot pulls the trigger, measured
## against its own error-offset aim point (see [method BotBrain.aim_towards]).
## Not zero: waiting for a perfect settle means a bot never shoots at anything
## that is moving.
const FIRE_CONE := 0.045   # ~2.6 degrees

## Reload during a lull once the magazine is this empty, the way a player does
## between fights rather than at the click.
const RELOAD_FRACTION := 0.3

var b: BotBrain

## Shots the burst is meant to contain, and the brain's shot counter when it
## began. Counting from the [signal WeaponController.fired] signal rather than
## from "ticks the trigger was held" means a burst is the same length whatever
## the weapon's fire rate is, and empty clicks do not count as shots.
var _burst_size: int = 0
var _shots_at_burst_start: int = 0
var _pause_left: float = 0.0

var _strafe: float = 1.0
var _strafe_left: float = 0.0

func _init(brain: BotBrain) -> void:
	id = &"bot_engage"
	b = brain

func enter(_from: StringName) -> void:
	_burst_size = 0
	# Not instant: the reaction time got them looking, this is the extra beat
	# between the gun coming up and the first round leaving it.
	_pause_left = b.profile.reaction_time * 0.5
	_strafe_left = 0.0
	_strafe = 1.0 if randf() < 0.5 else -1.0
	b.resample_aim_error(0.0)

func check_transitions(_cmd: InputCommand) -> StringName:
	if _should_retreat():
		return &"bot_retreat"
	if b.senses.visible_target != null:
		return &""
	if b.senses.time_since_seen <= LOST_CONTACT_GRACE:
		return &""
	return &"bot_hunt" if b.senses.has_last_known else &"bot_idle"

func physics_update(cmd: InputCommand, delta: float) -> void:
	var target := b.senses.visible_target
	var mark := b.senses.last_known_position + Vector3.UP * AIM_HEIGHT
	if target != null:
		mark = target.global_position + Vector3.UP * AIM_HEIGHT

	var aim_error := b.aim_towards(mark, delta)
	var distance := b.controller.global_position.distance_to(mark)
	_move(cmd, delta, mark, distance)
	_shoot(cmd, delta, target, distance, aim_error)

func _should_retreat() -> bool:
	if b.fight_commit > 0.0:
		return false
	var health := b.controller.health
	return health != null and health.fraction() <= b.profile.retreat_health

# --- feet -------------------------------------------------------------------

## Hold the profile's preferred range while strafing across the target.
##
## Strafing is not decoration. A bot that walks straight at you is trivial to
## track and dies to the first burst; one that moves laterally forces you to
## do the thing the movement system exists for. The strafe direction flips on
## a timer rather than at random each tick, because per-tick randomness
## averages out to standing still.
func _move(cmd: InputCommand, delta: float, mark: Vector3, distance: float) -> void:
	var to_target := mark - b.controller.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	var forward := to_target.normalized()
	var right := forward.cross(Vector3.UP).normalized()

	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(0.55, 1.4)
		_strafe = -_strafe

	# Aggression shifts the whole band inward: a pushy bot is happy closer than
	# its nominal preferred range and will keep closing rather than settle.
	var preferred: float = _preferred_range() * lerpf(1.15, 0.6, b.profile.aggression)
	var approach := 0.0
	if distance > preferred + b.profile.range_tolerance:
		approach = 1.0
	elif distance < preferred - b.profile.range_tolerance and b.profile.aggression < 0.8:
		approach = -0.8

	var lateral := lerpf(1.0, 0.45, absf(approach))
	var wanted := (forward * approach + right * (_strafe * lateral))
	if wanted.length_squared() < 0.001:
		return
	wanted = wanted.normalized()

	# One flip, then give up and hold position. Trying every direction until
	# something is walkable makes bots spin on the spot in a corner.
	if not b.can_step_towards(wanted, 1.6):
		_strafe = -_strafe
		_strafe_left = randf_range(0.5, 1.0)
		wanted = (forward * approach + right * (_strafe * lateral)).normalized()
		if not b.can_step_towards(wanted, 1.6):
			return
	b.move_in_direction(wanted, cmd)

# --- trigger ----------------------------------------------------------------

func _shoot(cmd: InputCommand, delta: float, target: Node3D, distance: float,
		aim_error: float) -> void:
	var rt := b.weapon()
	if rt == null:
		return

	# Sighted at range, hipfired up close, same as a player would. Aiming costs
	# movement speed, so a bot that always aimed would be a stationary target.
	cmd.aim_held = distance > _preferred_range() * 0.7

	if rt.magazine <= 0:
		cmd.reload_pressed = true
		_end_burst()
		return

	if _burst_size <= 0:
		_pause_left -= delta
		# The gap between bursts is where a player reloads, so it is where the
		# bot does too rather than running dry mid-fight.
		if rt.can_reload() and float(rt.magazine) <= rt.resource.magazine_size * RELOAD_FRACTION:
			cmd.reload_pressed = true
			return
		if _pause_left > 0.0:
			return
		_begin_burst(target)
		return

	if b.shots_fired - _shots_at_burst_start >= _burst_size:
		_end_burst()
		return

	# Do not shoot at a remembered position. Firing into the wall someone
	# vanished behind is the single most obvious way for a bot to look stupid.
	if target == null or aim_error > FIRE_CONE:
		return
	cmd.fire_pressed = true
	cmd.fire_held = true

func _begin_burst(target: Node3D) -> void:
	_burst_size = _burst_length()
	_shots_at_burst_start = b.shots_fired
	# Resampled per burst, not per tick: a wobble that changes every frame
	# averages to perfect aim across a burst, which is the exact opposite of
	# what an error model is for.
	b.resample_aim_error(_target_speed(target))

func _end_burst() -> void:
	_burst_size = 0
	_pause_left = randf_range(b.profile.burst_pause_min, b.profile.burst_pause_max)

## Where this bot wants to fight, given what it is holding.
##
## The profile's number is tuned against the rifle, and a shotgun bot that
## politely held 16 m would be firing pellets that do nothing. Rather than a
## second range field per weapon, the answer is already in the weapon: damage
## falloff says exactly where it stops being worth firing. Taking a quarter of
## the way into the falloff band leaves the rifle and pistol on the profile's
## number and pulls the shotgun in to about 8 m, which is where it wins.
func _preferred_range() -> float:
	var rt := b.weapon()
	if rt == null:
		return b.profile.preferred_range
	var res := rt.resource
	var effective: float = res.falloff_start + (res.falloff_end - res.falloff_start) * 0.25
	return minf(b.profile.preferred_range, effective)

## Burst length in shots, scaled so a burst takes about the same *time* on any
## weapon.
##
## The profile counts shots, and it is calibrated against the 600 rpm rifle. Six
## shots is a burst on a rifle and a four-second commitment on a shotgun, so the
## count is scaled by fire rate: slow, heavy weapons fire once and reassess,
## which is also how a player uses them.
func _burst_length() -> int:
	var wanted := randi_range(b.profile.burst_min, b.profile.burst_max)
	var rt := b.weapon()
	if rt == null:
		return wanted
	var scale: float = rt.resource.rounds_per_minute / 600.0
	return clampi(roundi(float(wanted) * scale), 1, wanted)

## How fast the target is moving across the bot's view -- movement toward or
## away is much easier to track, and should not be punished as if it were a
## strafe.
func _target_speed(target: Node3D) -> float:
	if target == null or not (target is CharacterBody3D):
		return 0.0
	var velocity: Vector3 = (target as CharacterBody3D).velocity
	velocity.y = 0.0
	var to_target := target.global_position - b.controller.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return velocity.length()
	var across := velocity - to_target.normalized() * velocity.dot(to_target.normalized())
	return across.length()
