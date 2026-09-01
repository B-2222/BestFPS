class_name HitboxRecorder
extends Node
## Per-tick history of a character's hitbox transforms.
##
## Nothing reads this yet. It exists because Milestone 5's lag compensation is
## exactly "put the hitboxes back where they were on tick N, trace, put them
## back" -- and that is only possible if someone was writing the history down
## the whole time. Adding it after weapons are tuned would change hit behaviour
## and force a re-tune, so it goes in with the first weapon.
##
## Cost is deliberately small: a ring buffer of [constant HISTORY_TICKS]
## entries, each a [PackedVector3Array] of origins plus a [Array] of basis
## values, overwritten in place with no allocation per tick.

## One second at 120 Hz. Comfortably covers any ping we would still try to
## compensate for; beyond about 250 ms, rewinding that far starts making
## "I was already behind cover" complaints legitimate.
const HISTORY_TICKS := 120

var _hitboxes: Array[Hitbox] = []
var _frames: Array = []
var _write_index: int = 0
var _first_tick: int = -1
var _last_tick: int = -1

func _ready() -> void:
	_collect_hitboxes(get_parent())
	_frames.resize(HISTORY_TICKS)
	for i in HISTORY_TICKS:
		_frames[i] = {"tick": -1, "transforms": []}

func _collect_hitboxes(node: Node) -> void:
	if node is Hitbox:
		_hitboxes.append(node)
	for child in node.get_children():
		_collect_hitboxes(child)

## Call once per physics tick, after the character has moved.
func record(tick: int) -> void:
	if _hitboxes.is_empty():
		return
	var transforms: Array[Transform3D] = []
	transforms.resize(_hitboxes.size())
	for i in _hitboxes.size():
		transforms[i] = _hitboxes[i].global_transform
	var frame: Dictionary = _frames[_write_index]
	frame["tick"] = tick
	frame["transforms"] = transforms
	_write_index = (_write_index + 1) % HISTORY_TICKS
	_last_tick = tick
	if _first_tick < 0:
		_first_tick = tick

## Transforms as of [param tick], or an empty array if that tick has aged out.
## Milestone 5 applies these before tracing and restores afterwards.
func transforms_at(tick: int) -> Array:
	for frame in _frames:
		if frame["tick"] == tick:
			return frame["transforms"]
	return []

func covers_tick(tick: int) -> bool:
	return tick >= _first_tick and tick <= _last_tick and not transforms_at(tick).is_empty()
