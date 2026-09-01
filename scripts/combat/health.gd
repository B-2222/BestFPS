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

var current: float = 0.0
var is_alive: bool = true

var _revive_timer: float = 0.0

func _ready() -> void:
	current = max_health

func _process(delta: float) -> void:
	if is_alive or auto_revive_after <= 0.0:
		return
	_revive_timer -= delta
	if _revive_timer <= 0.0:
		revive()

func apply_damage(info: DamageInfo) -> void:
	if not is_alive or info.amount <= 0.0:
		return
	current = maxf(current - info.amount, 0.0)
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
	revived.emit()

func fraction() -> float:
	return current / maxf(max_health, 0.001)
