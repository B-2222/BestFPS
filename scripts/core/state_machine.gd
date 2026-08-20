class_name StateMachine
extends RefCounted
## Flat finite state machine driving one actor.
##
## Deliberately minimal. Milestone 3 (bots) reuses this same class for AI
## behaviour, so it must not know anything about players, movement, or nodes.

## Emitted after the switch completes, so listeners observe the new state.
signal state_changed(from: StringName, to: StringName)

## Safety valve: a state whose transitions ping-pong would otherwise hang the
## frame. Four chained transitions in one tick is already generous.
const MAX_CHAINED_TRANSITIONS := 4

var current: State = null

var _states: Dictionary = {}

func add_state(state: State) -> void:
	if state.id == &"":
		push_error("StateMachine: state has no id; set it in _init().")
		return
	if _states.has(state.id):
		push_error("StateMachine: duplicate state id '%s'." % state.id)
		return
	state.machine = self
	_states[state.id] = state

func has_state(id: StringName) -> bool:
	return _states.has(id)

func start(id: StringName) -> void:
	if not _states.has(id):
		push_error("StateMachine: cannot start in unknown state '%s'." % id)
		return
	current = _states[id]
	current.enter(&"")
	state_changed.emit(&"", id)

func transition_to(id: StringName) -> void:
	if not _states.has(id):
		push_error("StateMachine: unknown state '%s'." % id)
		return
	if current != null and current.id == id:
		return
	var from: StringName = current.id if current != null else &""
	if current != null:
		current.exit(id)
	current = _states[id]
	current.enter(from)
	state_changed.emit(from, id)

## Resolve transitions first, then run exactly one state's update. The current
## state at the end of resolution is the one that gets to act this tick.
func update(cmd: InputCommand, delta: float) -> void:
	if current == null:
		return
	var guard := 0
	while guard < MAX_CHAINED_TRANSITIONS:
		var next: StringName = current.check_transitions(cmd)
		if next == &"" or next == current.id:
			break
		transition_to(next)
		guard += 1
	current.physics_update(cmd, delta)
