class_name InputCommand
extends RefCounted
## One tick of intent, as data.
##
## This is the single most important seam in the project. Movement code reads
## *only* this struct -- never the [Input] singleton. Three things fall out of
## that, and all three are expensive to retrofit later:
##
## 1. Bots (Milestone 3) drive the exact same movement code by filling one of
##    these from an AI decision, so bots move like players by construction
##    rather than by a second, drifting implementation.
## 2. Networked remote players (Milestone 5) are simulated by replaying
##    received commands through the same code path.
## 3. Client-side prediction needs to re-simulate a *range* of past ticks after
##    a server correction. That is only possible if a tick's input is a value
##    you can store and replay.
##
## Look is carried as absolute [member yaw]/[member pitch] rather than a mouse
## delta: deltas are frame-rate dependent and unreplayable, angles are neither.

## Movement intent in local space. x = strafe (+right), y = forward (+forward).
## Magnitude is clamped to 1 so diagonal movement is not faster (the classic
## "strafe running" bug) while still leaving room for analog sticks.
var move_axis: Vector2 = Vector2.ZERO

## Absolute view angles in radians at the time this command was sampled.
var yaw: float = 0.0
var pitch: float = 0.0

## Edge-triggered. Valid for exactly one tick; cleared by
## [method clear_one_shots] at the end of the controller's physics step.
var jump_pressed: bool = false
var crouch_pressed: bool = false

## Level-triggered, valid for as long as the key is down.
var jump_held: bool = false
var crouch_held: bool = false
var sprint_held: bool = false

## Monotonic tick counter. Unused in Milestone 1; it is the acknowledgement key
## the netcode will need, and costs nothing to carry now.
var tick: int = 0

func clear() -> void:
	move_axis = Vector2.ZERO
	jump_pressed = false
	jump_held = false
	crouch_pressed = false
	crouch_held = false
	sprint_held = false

## Consume edge-triggered inputs. Called once per tick, after the movement
## code has had its chance to see them.
func clear_one_shots() -> void:
	jump_pressed = false
	crouch_pressed = false

func duplicate_command() -> InputCommand:
	var c := InputCommand.new()
	c.move_axis = move_axis
	c.yaw = yaw
	c.pitch = pitch
	c.jump_pressed = jump_pressed
	c.jump_held = jump_held
	c.crouch_pressed = crouch_pressed
	c.crouch_held = crouch_held
	c.sprint_held = sprint_held
	c.tick = tick
	return c
