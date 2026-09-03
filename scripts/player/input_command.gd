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

## Monotonic tick counter. The acknowledgement key the netcode needs, and --
## from Milestone 2 on -- the seed source for deterministic weapon spread, so
## the client and server independently compute the same pellet directions.
var tick: int = 0

# --- combat (Milestone 2) --------------------------------------------------

## Edge-triggered: semi-automatic weapons fire on this.
var fire_pressed: bool = false
## Level-triggered: automatic weapons fire while this is held.
var fire_held: bool = false
var reload_pressed: bool = false
var aim_held: bool = false

## Requested weapon slot, or -1 for "no change". An absolute slot rather than a
## "next weapon" pulse, because a dropped or reordered packet must not leave the
## server holding a different weapon than the client is drawing.
var weapon_slot: int = -1

func clear() -> void:
	move_axis = Vector2.ZERO
	jump_pressed = false
	jump_held = false
	crouch_pressed = false
	crouch_held = false
	sprint_held = false
	fire_pressed = false
	fire_held = false
	reload_pressed = false
	aim_held = false
	weapon_slot = -1

## Consume edge-triggered inputs. Called once per tick, after the movement
## code has had its chance to see them.
func clear_one_shots() -> void:
	jump_pressed = false
	crouch_pressed = false
	fire_pressed = false
	reload_pressed = false
	weapon_slot = -1

## Pack into something an RPC can carry.
##
## An Array of primitives rather than a bit-packed PackedByteArray. On a LAN
## the difference is a few hundred bytes a second against a link with megabytes
## to spare, and a readable encoding is worth far more right now than a saving
## nobody can measure. Bit-packing is the optimisation for internet play, and it
## is contained to these two functions when it happens.
##
## The buttons travel as one bitfield because they are booleans and a bitfield
## is the one place packing costs nothing in clarity.
func to_wire() -> Array:
	var buttons := 0
	if jump_pressed: buttons |= 1
	if jump_held: buttons |= 2
	if crouch_pressed: buttons |= 4
	if crouch_held: buttons |= 8
	if sprint_held: buttons |= 16
	if fire_pressed: buttons |= 32
	if fire_held: buttons |= 64
	if reload_pressed: buttons |= 128
	if aim_held: buttons |= 256
	return [tick, move_axis.x, move_axis.y, yaw, pitch, buttons, weapon_slot]

## Unpack, defensively. This is data from another machine, so a short or
## malformed array must leave the command untouched rather than half-applied --
## a half-applied command is a character that walks somewhere nobody asked it
## to, which is indistinguishable from a physics bug.
func from_wire(wire: Array) -> bool:
	if wire.size() != 7:
		return false
	tick = int(wire[0])
	move_axis = Vector2(float(wire[1]), float(wire[2])).limit_length(1.0)
	yaw = float(wire[3])
	pitch = float(wire[4])
	var buttons := int(wire[5])
	jump_pressed = (buttons & 1) != 0
	jump_held = (buttons & 2) != 0
	crouch_pressed = (buttons & 4) != 0
	crouch_held = (buttons & 8) != 0
	sprint_held = (buttons & 16) != 0
	fire_pressed = (buttons & 32) != 0
	fire_held = (buttons & 64) != 0
	reload_pressed = (buttons & 128) != 0
	aim_held = (buttons & 256) != 0
	weapon_slot = clampi(int(wire[6]), -1, 9)
	return true

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
	c.fire_pressed = fire_pressed
	c.fire_held = fire_held
	c.reload_pressed = reload_pressed
	c.aim_held = aim_held
	c.weapon_slot = weapon_slot
	c.tick = tick
	return c
