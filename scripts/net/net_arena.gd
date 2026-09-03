class_name NetArena
extends Node3D
## Puts a character in the world for every connected player, and keeps them in
## step.
##
## ## The model
##
## The host simulates everything and is right about everything. Clients send
## their [InputCommand] every tick and receive a snapshot of the world back.
## The host runs remote players through [NetInputSource], which feeds the same
## `fill_command` call the local player and the bots use -- so there is exactly
## one movement implementation and one weapon implementation, and being remote
## cannot make a character behave differently. That was the whole point of
## making input a value back in M1.
##
## ## Prediction, and what is deferred
##
## A client applies its own input immediately rather than waiting for the host
## to confirm it, because a round trip of input lag is instantly noticeable
## even on a LAN. The host's snapshot then corrects it, eased in over a few
## ticks rather than snapped, so a small disagreement does not show as a
## twitch.
##
## Full rollback-and-replay reconciliation -- rewinding to the acknowledged
## tick and re-simulating every command since -- is **not** implemented, and
## that is a deliberate scoping decision rather than an oversight. On a LAN the
## disagreement it exists to fix is sub-centimetre, and replaying movement in
## Godot means re-running move_and_slide against collision state that has
## already moved on, so it is approximate anyway. It becomes worth building
## when this game is played over the internet; see docs/networking-decision.md.

## How often the host sends the world out. The simulation runs at 120 Hz, but
## sending at 120 Hz is bandwidth spent on detail no one can see -- clients
## interpolate between snapshots, so the rate sets smoothness, not accuracy.
const SNAPSHOT_HZ := 30.0
## Seconds a correction is eased over on the predicting client.
const CORRECTION_SECONDS := 0.12
## Beyond this the client has diverged too far to ease back and is snapped.
## Usually means it was paused, or missed a teleport such as a respawn.
const SNAP_DISTANCE := 3.0

const REMOTE_SCENE := "res://scenes/player/player.tscn"

@export var local_player_path: NodePath = ^"../Player"
@export var director_path: NodePath = ^"../BotDirector"

## Id space. Players are their positive peer id; the two bot rosters get
## separate negative ranges so an index can never be mistaken for the other
## roster's, which would show up as two bots sharing one body.
const ROAM_BOT_BASE := -1
const DUEL_BOT_BASE := -1000
## A ghost nobody has mentioned for this long has left. Snapshots are the only
## evidence a client has that somebody is still in the game.
const GHOST_TIMEOUT := 2.0

## Host only: peer id -> the character it simulates for that player.
var remotes: Dictionary = {}
## Client only: id -> a body it draws but does not simulate. Created on demand
## from whatever a snapshot mentions, which means a client needs to know
## nothing about the roster, the bot count or the duel wing to render them --
## the snapshot is the whole contract.
var ghosts: Dictionary = {}

var _session: NetSession
var _local: PlayerController
var _director: BotDirector
## peer id -> NetInputSource, host only.
var _inputs: Dictionary = {}
var _snapshot_accumulator: float = 0.0
var _tick: int = 0
## Where the host has told us each character should be, and how long the ease
## has left to run. Client only.
var _corrections: Dictionary = {}
## id -> seconds since a snapshot last mentioned it.
var _ghost_age: Dictionary = {}

func _ready() -> void:
	_local = get_node_or_null(local_player_path) as PlayerController
	_director = get_node_or_null(director_path) as BotDirector
	_session = get_node_or_null(^"/root/Net") as NetSession
	if _session == null:
		# No networking in this build or this test. Everything below is a no-op
		# and the arena behaves exactly as it did before multiplayer existed,
		# which is what keeps the single-player build and the other suites
		# unaffected.
		set_physics_process(false)
		return
	_session.lobby_changed.connect(_sync_roster)
	_session.link_changed.connect(_on_link_changed)
	_sync_roster()

func _on_link_changed(_link: NetSession.Link) -> void:
	# Bots are simulated by whoever is authoritative, and only by them. Left
	# running on a client they would be a second, disagreeing copy of every bot
	# in the game.
	if _director != null:
		_director.process_mode = Node.PROCESS_MODE_INHERIT if _session.is_authority() \
				else Node.PROCESS_MODE_DISABLED
	_sync_roster()

## Add and remove characters so the world matches the lobby.
##
## Host only. A client does not spawn from the roster at all -- it draws
## whatever the snapshot mentions and nothing else, so there is one source of
## truth for who exists rather than two that can disagree.
func _sync_roster() -> void:
	if _session == null or not _session.is_authority():
		return
	var wanted := {}
	for peer_id in _session.roster.keys():
		if peer_id != multiplayer.get_unique_id():
			wanted[peer_id] = true

	for peer_id in remotes.keys():
		if not wanted.has(peer_id):
			_remove_remote(peer_id)
	for peer_id in wanted.keys():
		if not remotes.has(peer_id):
			_add_remote(peer_id)

func _add_remote(peer_id: int) -> void:
	var scene := load(REMOTE_SCENE) as PackedScene
	if scene == null:
		return
	var character := scene.instantiate() as PlayerController
	if character == null:
		return
	character.name = "Peer%d" % peer_id
	# Somebody else's character is seen, not looked through: it needs a body,
	# and it must not steal the camera or read this machine's keyboard.
	character.show_body = true
	character.input_source_path = ^""
	character.position = _spawn_point(peer_id)
	add_child(character)
	_strip_local_only_nodes(character)

	if _session.is_authority():
		var source := NetInputSource.new()
		source.name = "NetInput"
		character.add_child(source)
		character.set_input_source(source)
		_inputs[peer_id] = source
	remotes[peer_id] = character

## Remove the parts of the player scene that only make sense for the person
## sitting at this machine. A second Camera3D with `current` set would fight the
## local one for the viewport, and a second AudioDirector would play another
## copy of every footstep in your ears.
func _strip_local_only_nodes(character: PlayerController) -> void:
	# The whole camera arm, not its children one at a time. CameraRig holds a
	# reference to the camera and keeps writing to it, so removing the camera
	# and leaving the rig produces a stream of "previously freed" errors every
	# frame for the rest of the session.
	for path in [^"PlayerInput", ^"AudioDirector", ^"Head/CameraArm"]:
		var node := character.get_node_or_null(path)
		if node != null:
			node.get_parent().remove_child(node)
			node.queue_free()

func _remove_remote(peer_id: int) -> void:
	var character: PlayerController = remotes.get(peer_id)
	if is_instance_valid(character):
		character.queue_free()
	remotes.erase(peer_id)
	_inputs.erase(peer_id)
	_corrections.erase(peer_id)

## Spread spawns around the arena deterministically, so host and client agree
## on where somebody started without having to send it.
func _spawn_point(peer_id: int) -> Vector3:
	var angle := float(peer_id) * 2.399963   # golden angle, in radians
	return Vector3(sin(angle) * 12.0, 1.0, cos(angle) * 12.0)

# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _session == null or _session.link == NetSession.Link.OFFLINE:
		return
	_tick += 1
	if _session.is_authority():
		_host_tick(delta)
	else:
		_client_tick(delta)

func _host_tick(delta: float) -> void:
	_snapshot_accumulator += delta
	if _snapshot_accumulator < 1.0 / SNAPSHOT_HZ:
		return
	_snapshot_accumulator = 0.0
	var snapshot := _build_snapshot()
	if not snapshot.is_empty():
		# Unreliable and unordered on purpose. A snapshot is a complete picture
		# of now, so a lost one is replaced by the next one 33 ms later -- and
		# resending a stale world is worse than skipping it.
		_receive_snapshot.rpc(snapshot)

func _client_tick(_delta: float) -> void:
	if _local == null:
		return
	# The command the local player just acted on, sent to the host so it can
	# act on the same one.
	_send_command.rpc_id(NetSession.HOST_ID, _local.cmd.to_wire())
	_apply_corrections(_delta)
	_expire_ghosts(_delta)

func _build_snapshot() -> Array:
	var out: Array = []
	if _local != null:
		out.append(_capture(multiplayer.get_unique_id(), _local))
	for peer_id in remotes.keys():
		var character: PlayerController = remotes[peer_id]
		if is_instance_valid(character):
			out.append(_capture(peer_id, character))
	if _director != null:
		for i in _director.bots.size():
			var bot: PlayerController = _director.bots[i]
			if is_instance_valid(bot):
				out.append(_capture(ROAM_BOT_BASE - i, bot))
		for i in _director.duel_bots.size():
			var duel: PlayerController = _director.duel_bots[i]
			if is_instance_valid(duel):
				out.append(_capture(DUEL_BOT_BASE - i, duel))
	return out

## One character, as the wire sees it. Negative ids are bots, which is enough
## to tell them apart without a second field.
func _capture(id: int, character: PlayerController) -> Array:
	return [id, character.global_position.x, character.global_position.y,
			character.global_position.z, character.yaw, character.pitch,
			character.velocity.x, character.velocity.y, character.velocity.z,
			character.health.current if character.health != null else 100.0]

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_command(wire: Array) -> void:
	if not _session.is_authority():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var source: NetInputSource = _inputs.get(peer_id)
	if source == null:
		return
	source.accept(wire)

@rpc("authority", "call_remote", "unreliable")
func _receive_snapshot(snapshot: Array) -> void:
	if _session.is_authority():
		return
	for entry in snapshot:
		if not entry is Array or (entry as Array).size() != 10:
			continue
		var id := int(entry[0])
		_ghost_age[id] = 0.0
		var character := _character_for(id)
		if character == null:
			character = _ensure_ghost(id)
		if character == null:
			continue
		if id == multiplayer.get_unique_id():
			_corrections[id] = {"target": Vector3(entry[1], entry[2], entry[3]),
					"left": CORRECTION_SECONDS}
			if character.health != null:
				character.health.current = float(entry[9])
			continue
		# Everyone else is placed where the host says, with their aim applied
		# directly: a remote player's head is the thing you shoot at, and
		# smoothing it would mean shooting at somewhere they are not.
		character.global_position = Vector3(entry[1], entry[2], entry[3])
		character.velocity = Vector3(entry[6], entry[7], entry[8])
		character.yaw = float(entry[4])
		character.pitch = float(entry[5])
		character.apply_view()
		if character.health != null:
			character.health.current = float(entry[9])

## Ease the local player toward what the host says, rather than snapping.
func _apply_corrections(delta: float) -> void:
	for id in _corrections.keys():
		var correction: Dictionary = _corrections[id]
		var character := _character_for(id)
		if character == null:
			_corrections.erase(id)
			continue
		var target: Vector3 = correction["target"]
		var error := target - character.global_position
		if error.length() > SNAP_DISTANCE:
			character.global_position = target
			_corrections.erase(id)
			continue
		var left: float = correction["left"] - delta
		if left <= 0.0:
			_corrections.erase(id)
			continue
		correction["left"] = left
		character.global_position += error * minf(delta / CORRECTION_SECONDS, 1.0)

## A body for something this machine does not simulate.
func _ensure_ghost(id: int) -> PlayerController:
	if _session.is_authority():
		return null   # the host simulates everything; it never needs a ghost
	var scene := load(REMOTE_SCENE) as PackedScene
	if scene == null:
		return null
	var character := scene.instantiate() as PlayerController
	if character == null:
		return null
	character.name = "Ghost%d" % id
	character.show_body = true
	character.input_source_path = ^""
	add_child(character)
	_strip_local_only_nodes(character)
	# A ghost is placed by snapshots, so it must not also fall, slide or be
	# pushed -- two things moving one body disagree, and the disagreement looks
	# exactly like lag.
	character.set_physics_process(false)
	ghosts[id] = character
	return character

## Free ghosts nothing has mentioned lately: someone who left, a bot the host
## despawned, a duel room switched off.
func _expire_ghosts(delta: float) -> void:
	for id in ghosts.keys():
		var age: float = float(_ghost_age.get(id, 0.0)) + delta
		_ghost_age[id] = age
		if age < GHOST_TIMEOUT:
			continue
		var character: PlayerController = ghosts[id]
		if is_instance_valid(character):
			character.queue_free()
		ghosts.erase(id)
		_ghost_age.erase(id)

func _character_for(id: int) -> PlayerController:
	if id == multiplayer.get_unique_id():
		return _local
	if _session.is_authority():
		if id > 0:
			var remote: PlayerController = remotes.get(id)
			return remote if is_instance_valid(remote) else null
		var roster: Array = _director.bots if id > DUEL_BOT_BASE \
				else _director.duel_bots
		var base := ROAM_BOT_BASE if id > DUEL_BOT_BASE else DUEL_BOT_BASE
		var index := base - id
		if _director == null or index < 0 or index >= roster.size():
			return null
		var bot: PlayerController = roster[index]
		return bot if is_instance_valid(bot) else null
	var ghost: PlayerController = ghosts.get(id)
	return ghost if is_instance_valid(ghost) else null
