class_name BotHuntState
extends State
## Something was seen or heard. Go and look at where it was.
##
## Deliberately paths to the *last known* position rather than the target's
## live one. A bot that walks straight to where you actually are, through
## walls it cannot see through, is the clearest possible tell that it is
## cheating -- and losing them by breaking line of sight is most of what
## positioning is for.

var b: BotBrain

## Same reasoning as [BotRetreatState]: a freshly issued path reports itself
## finished until it has been solved, and giving up on the first tick would
## mean the bot forgets the target it just heard without taking a step.
const SETTLE_SECONDS := 0.3

var _settle: float = 0.0

func _init(brain: BotBrain) -> void:
	id = &"bot_hunt"
	b = brain

func enter(_from: StringName) -> void:
	_settle = SETTLE_SECONDS
	b.set_goal(b.senses.last_known_position)

func check_transitions(_cmd: InputCommand) -> StringName:
	if b.senses.visible_target != null and b.senses.time_in_view >= b.profile.reaction_time:
		return &"bot_engage"
	if not b.senses.has_last_known:
		return &"bot_idle"
	return &""

func physics_update(cmd: InputCommand, delta: float) -> void:
	_settle = maxf(_settle - delta, 0.0)
	b.set_goal(b.senses.last_known_position)
	var travelling := b.follow_path(cmd)
	# Look where it is going, so it is not walking sideways into a fight.
	var look := b.senses.last_known_position
	if travelling and b.agent != null:
		look = b.agent.get_next_path_position()
	b.reload_if_out_of_contact(cmd)
	b.aim_towards(look + Vector3.UP * 1.2, delta)
	if not travelling and _settle <= 0.0:
		# Arrived and found nothing. Forget it and go back to scanning.
		b.senses.has_last_known = false
