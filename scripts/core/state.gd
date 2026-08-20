class_name State
extends RefCounted
## Base class for a single state in a [StateMachine].
##
## Two-phase design: [method check_transitions] decides *whether* to leave,
## [method physics_update] does the work. Keeping them apart stops the classic
## FSM bug where a state mutates the world and then exits in the same tick,
## leaving the successor to clean up half-applied changes.
##
## States are [RefCounted], not [Node], on purpose. One instance per actor with
## no scene-tree overhead, cheap to build, and re-runnable -- which is what
## client-side prediction will need in Milestone 5 (see docs/architecture.md).

## Identifier used to register and address this state. Set it in [method _init].
var id: StringName = &""

## Owning machine. Held weakly and deliberately untyped. Weakly because the
## machine holds its states strongly, and GDScript's [RefCounted] is plain
## reference counting with no cycle collector -- a strong back-pointer would
## leak the whole machine plus every state for each actor that is ever freed.
## Untyped because naming [StateMachine] here would create a class_name
## reference cycle between the two files.
var machine:
	get:
		return _machine_ref.get_ref() if _machine_ref != null else null
	set(value):
		_machine_ref = weakref(value) if value != null else null

var _machine_ref: WeakRef = null

## Called once when this state becomes current.
func enter(_from: StringName) -> void:
	pass

## Called once when this state stops being current.
func exit(_to: StringName) -> void:
	pass

## Return the id of the state to switch to, or [code]&""[/code] to stay put.
## Must not mutate anything -- it may be called and discarded.
func check_transitions(_cmd: InputCommand) -> StringName:
	return &""

## Per-physics-tick work for this state.
func physics_update(_cmd: InputCommand, _delta: float) -> void:
	pass
