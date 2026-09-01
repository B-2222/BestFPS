class_name BotIdleState
extends State
## Nothing to chase. Stand and scan.

var b: BotBrain
var _scan_direction: float = 1.0
var _scan_timer: float = 0.0

func _init(brain: BotBrain) -> void:
	id = &"bot_idle"
	b = brain

func enter(_from: StringName) -> void:
	_scan_timer = 0.0

func check_transitions(_cmd: InputCommand) -> StringName:
	if b.senses.visible_target != null and b.senses.time_in_view >= b.profile.reaction_time:
		return &"bot_engage"
	if b.senses.has_last_known:
		return &"bot_hunt"
	return &""

func physics_update(cmd: InputCommand, delta: float) -> void:
	# Sweep the view slowly. A bot that stares at one wall is trivially
	# flankable in a way that reads as broken rather than as an opening.
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = randf_range(1.6, 3.2)
		_scan_direction = -_scan_direction
	b.reload_if_out_of_contact(cmd)
	b.controller.yaw = wrapf(b.controller.yaw + _scan_direction * 0.6 * delta, -PI, PI)
	b.controller.pitch = move_toward(b.controller.pitch, 0.0, delta)
	b.controller.apply_view()
