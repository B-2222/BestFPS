class_name BotRetreatState
extends State
## Hurt. Break contact instead of trading a fight it is going to lose.
##
## This is a repositioning move, not a heal-and-return: the bot backs away from
## where the shots came from, keeping its gun pointed at the threat so it can
## still punish a careless push, and re-enters the fight from somewhere else.
## Health regeneration (see [Health]) may top it up on the way if it stays out
## of contact long enough, which is the same deal the player gets.
##
## Leaving this state sets [member BotBrain.fight_commit], so a bot that has
## just retreated will not immediately retreat again. Without that, a bot
## hovering on its health threshold oscillates between fighting and fleeing
## every few ticks and never does either -- which looks like a bug, not like
## fear.

## How long to keep backing off before returning to the fight.
const RETREAT_SECONDS := 3.2

## And how long it is then obliged to stand and fight for.
const COMMIT_SECONDS := 5.0

## Distance to put between itself and the threat.
const FALLBACK_DISTANCE := 14.0

const AIM_HEIGHT := 1.2

var b: BotBrain

var _timer: float = 0.0
var _repath: float = 0.0

func _init(brain: BotBrain) -> void:
	id = &"bot_retreat"
	b = brain

func enter(_from: StringName) -> void:
	_timer = RETREAT_SECONDS
	_repath = 0.0

func exit(_to: StringName) -> void:
	b.fight_commit = COMMIT_SECONDS

func check_transitions(_cmd: InputCommand) -> StringName:
	if _timer > 0.0:
		return &""
	if b.senses.visible_target != null:
		return &"bot_engage"
	return &"bot_hunt" if b.senses.has_last_known else &"bot_idle"

func physics_update(cmd: InputCommand, delta: float) -> void:
	_timer -= delta

	var threat := b.senses.last_known_position
	if b.senses.visible_target != null:
		threat = b.senses.visible_target.global_position

	# Repathed on a timer rather than every tick: the destination is derived
	# from a moving threat, and re-solving a path 120 times a second to a
	# target that drifts a few centimetres is pure cost.
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.5
		var away := b.controller.global_position - threat
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -b.controller.global_transform.basis.z
		b.set_goal(b.nav_point_towards(away.normalized(), FALLBACK_DISTANCE))

	# The "cornered" test is deliberately not applied on the first few ticks:
	# the agent reports a finished navigation until it has actually solved the
	# path it was just handed, and reading that as "nowhere to run" would abort
	# every retreat the instant it started.
	if not b.follow_path(cmd) and _timer < RETREAT_SECONDS - 0.3:
		# Nowhere left to fall back to -- cornered. Stop running and fight.
		_timer = 0.0

	# Keep facing the threat while withdrawing. The path is walked with the
	# movement stick, and the stick is in local space, so backpedalling out of
	# a fight while still covering it costs nothing extra.
	b.aim_towards(threat + Vector3.UP * AIM_HEIGHT, delta)

	var rt := b.weapon()
	if rt == null:
		return
	# Reload while withdrawing. This is most of the value of retreating at all.
	if rt.can_reload() and rt.magazine < rt.resource.magazine_size:
		cmd.reload_pressed = true
