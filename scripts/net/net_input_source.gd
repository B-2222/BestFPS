class_name NetInputSource
extends Node
## Fills a [PlayerController]'s command from what arrived over the network.
##
## The same shape as [PlayerInput] and [BotBrain]: one `fill_command` call, and
## the controller never learns where its intent came from. That is the third
## thing the InputCommand seam has bought, and the one it was designed for.
##
## Lives on the host, one per connected player. The host simulates every
## character with the same movement and weapon code the local player runs, so
## a remote player cannot move differently to a local one -- there is only one
## implementation and it is not parameterised by who is driving it.

## Ticks to keep replaying the last command when nothing new has arrived.
##
## A dropped packet or a stalled sender should not make a running player stop
## dead, which reads as a rubber-band. Repeating the last input for a short
## while carries them through a gap; beyond that they really have stopped
## talking and standing still is the honest answer.
const COAST_TICKS := 12

## Highest tick accepted so far. Commands are UDP, so they arrive out of order
## and duplicated; anything not newer than this is dropped rather than applied,
## which would teleport a player back in time.
var last_tick: int = -1
## Set while the sender is quiet, for anything that wants to show a connection
## problem.
var is_stale: bool = false

var _command := InputCommand.new()
var _coast: int = 0

## Feed one command from the wire. Returns false if it was rejected.
func accept(wire: Array) -> bool:
	var candidate := InputCommand.new()
	if not candidate.from_wire(wire):
		return false
	if candidate.tick <= last_tick:
		return false
	last_tick = candidate.tick
	_command = candidate
	_coast = COAST_TICKS
	is_stale = false
	return true

func fill_command(cmd: InputCommand, _delta: float) -> void:
	if _coast <= 0:
		is_stale = true
		# Aim is held rather than cleared: a disconnected player's character
		# freezing mid-stride is expected, but their head snapping to face
		# north is not.
		cmd.clear()
		cmd.yaw = _command.yaw
		cmd.pitch = _command.pitch
		return
	_coast -= 1

	cmd.move_axis = _command.move_axis
	cmd.yaw = _command.yaw
	cmd.pitch = _command.pitch
	cmd.jump_held = _command.jump_held
	cmd.crouch_held = _command.crouch_held
	cmd.sprint_held = _command.sprint_held
	cmd.fire_held = _command.fire_held
	cmd.aim_held = _command.aim_held
	# Edge-triggered fields are handed over exactly once, then cleared on the
	# stored copy. Replaying them while coasting would fire a weapon repeatedly
	# from a single click, which is both wrong and the sort of wrong that looks
	# like cheating from the other end.
	cmd.jump_pressed = _command.jump_pressed
	cmd.crouch_pressed = _command.crouch_pressed
	cmd.fire_pressed = _command.fire_pressed
	cmd.reload_pressed = _command.reload_pressed
	cmd.weapon_slot = _command.weapon_slot
	_command.clear_one_shots()
