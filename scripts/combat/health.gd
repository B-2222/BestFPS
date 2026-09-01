class_name Health
extends Node
## Hit points, and the single mutation path for them.
##
## Nothing outside this class writes [member current]. That is deliberate: in
## Milestone 5 the server becomes the only legitimate caller of
## [method apply_damage], and making that change has to be a change in one
## place rather than an audit of everywhere damage is dealt.

signal damaged(info: DamageInfo, remaining: float)
signal healed(amount: float, remaining: float)
signal died(info: DamageInfo)
signal revived()

@export var max_health: float = 100.0
## Seconds before an automatic revive. 0 disables it. The target dummies use
## this so the range never runs out of things to shoot.
@export var auto_revive_after: float = 3.0

## Seconds out of contact before health starts coming back. 0 disables
## regeneration entirely, which is what the practice-range dummies want.
##
## Regeneration is a real design decision, not a convenience. Without it, one
## unlucky trade leaves you at 14 HP for the rest of the session and every
## subsequent fight is decided before it starts -- so the match degenerates
## into avoiding fights, which is the opposite of what an arena is for. With
## it, a fight has a cost you can pay back by disengaging, which is what makes
## backing off a decision instead of a loss.
##
## The delay is the whole tuning knob: long enough that it never helps mid
## fight, short enough that you are not walking around waiting.
@export var regen_delay: float = 6.0
@export var regen_per_second: float = 22.0

var current: float = 0.0
var is_alive: bool = true

var _revive_timer: float = 0.0
var _time_since_damage: float = 999.0

func _ready() -> void:
	current = max_health

func _process(delta: float) -> void:
	if not is_alive:
		if auto_revive_after <= 0.0:
			return
		_revive_timer -= delta
		if _revive_timer <= 0.0:
			revive()
		return

	_time_since_damage += delta
	if regen_delay <= 0.0 or regen_per_second <= 0.0:
		return
	if _time_since_damage < regen_delay or current >= max_health:
		return
	heal(regen_per_second * delta)

func apply_damage(info: DamageInfo) -> void:
	if not is_alive or info.amount <= 0.0:
		return
	current = maxf(current - info.amount, 0.0)
	_time_since_damage = 0.0
	damaged.emit(info, current)
	if current <= 0.0:
		is_alive = false
		_revive_timer = auto_revive_after
		died.emit(info)

func heal(amount: float) -> void:
	if not is_alive or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	healed.emit(amount, current)

func revive() -> void:
	current = max_health
	is_alive = true
	_time_since_damage = 999.0
	revived.emit()

func fraction() -> float:
	return current / maxf(max_health, 0.001)
