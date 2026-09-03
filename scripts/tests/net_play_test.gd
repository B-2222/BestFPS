extends SceneTree
## End-to-end multiplayer check, run as two processes.
##
##   godot --headless --script scripts/tests/net_play_test.gd -- --host
##   godot --headless --script scripts/tests/net_play_test.gd -- --join CODE
##
## scripts/tests/run_net_play.sh drives both and requires both to pass.
##
## Two processes rather than two sub-trees in one, because the thing worth
## proving is the part a single process cannot exercise honestly: a real socket,
## real serialisation, real packet loss handling, and two independent copies of
## the arena that have to agree about where everybody is.
##
## Each side asserts the half it can see:
##
## - The **host** proves input replication works: the joining client's character
##   only moves if its InputCommands crossed the wire and were fed through
##   NetInputSource into the same movement code the local player uses.
## - The **client** proves state replication works: it has no idea where the
##   host's character is except from snapshots, so finding it at the agreed
##   position means the snapshot path is sound end to end.

## Where the host parks its character. The client checks for it here.
const HOST_MARK := Vector3(7.0, 1.0, -3.0)
## How far apart the two machines may believe a character is.
const TOLERANCE := 1.5
## Ticks before giving up. 120 Hz, so this is about twelve seconds.
const DEADLINE := 1440
## The client walks for this many ticks so the host can see it move.
const WALK_TICKS := 240
## The host stays up at least this long, so the client finishes first.
const LINGER_TICKS := 600

var _arena: Node
var _player: PlayerController
var _net_arena: NetArena
var _session: NetSession

var _is_host := false
var _tick := 0
var _failures: PackedStringArray = PackedStringArray()
var _checks := 0
var _done := false

var _client_start := Vector3.ZERO
var _client_moved := 0.0
var _saw_host_ghost := false
var _code := ""
## Recorded from the signal rather than read at the end. The host quits as soon
## as it has what it needs, which tears the client's link down before the
## client's own checks run -- so a live read would report OFFLINE on a session
## that connected perfectly well.
var _was_connected := false
var _ghost_error := 999.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_is_host = args.has("--host")
	_session = root.get_node_or_null(^"Net") as NetSession
	if _session != null:
		_session.link_changed.connect(func(link: NetSession.Link) -> void:
			if link == NetSession.Link.CONNECTED:
				_was_connected = true)
	if _session == null:
		print("net play test: the Net autoload is missing")
		quit(1)
		return

	_arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	root.add_child(_arena)
	_player = _arena.get_node("Player") as PlayerController
	_net_arena = _arena.get_node("NetArena") as NetArena
	# Bots off on both sides. They are replicated by the same path as players
	# and would only add noise to what is being measured here.
	var director := _arena.get_node_or_null(^"BotDirector") as BotDirector
	if director != null:
		director.bot_count = 0
		director.duel_pits_enabled = false

	_code = ""
	var index := args.find("--join")
	if index >= 0 and index + 1 < args.size():
		_code = args[index + 1]
	print("=== net play test (%s) ===" % ["host" if _is_host else "client"])
	if _is_host:
		print("CODE %s" % JoinCode.encode("127.0.0.1", NetSession.DEFAULT_PORT))

## Connecting happens on the first tick, not in _initialize(). A node's
## multiplayer API resolves through the tree and is still null while the tree
## is coming up, so hosting from _initialize() silently assigns a peer to
## nothing.
func _connect_now() -> void:
	if _is_host:
		_session.host("Host")
	else:
		_session.join(_code, "Joiner")

func _physics_process(delta: float) -> bool:
	if _done:
		return true
	_tick += 1
	if _tick == 2:
		_connect_now()
	if _tick < 2:
		return false
	if _is_host:
		_host_step()
	else:
		_client_step(delta)
	if _tick > DEADLINE:
		return _finish()
	return false

# ---------------------------------------------------------------------------

func _host_step() -> void:
	# Parked somewhere the client can check for, and held there so a physics
	# nudge cannot drift it out of tolerance during the run.
	_player.set_input_source(null)
	_player.cmd.clear()
	_player.global_position = HOST_MARK
	_player.velocity = Vector3.ZERO

	# Watch the joining client's character. It has no input source of its own
	# on this machine except the one fed from the network.
	for peer_id in _net_arena.remotes.keys():
		var character: PlayerController = _net_arena.remotes[peer_id]
		if not is_instance_valid(character):
			continue
		if _client_start == Vector3.ZERO:
			_client_start = character.global_position
		_client_moved = maxf(_client_moved,
				character.global_position.distance_to(_client_start))

	# Deliberately does not stop the moment it has what it needs. Quitting here
	# closes the socket, and the client is still running its own checks against
	# a session that would then read as offline.
	if _client_moved > 2.0 and _session.roster.size() >= 2 and _tick > LINGER_TICKS:
		_finish()

func _client_step(_delta: float) -> void:
	# Walk, so the host has something to observe. Driven straight into the
	# command, which is exactly what a real keyboard would fill in.
	_player.set_input_source(null)
	_player.cmd.clear()
	if _tick > 120 and _tick < 120 + WALK_TICKS:
		_player.cmd.move_axis = Vector2(0.0, 1.0)

	for id in _net_arena.ghosts.keys():
		if id != NetSession.HOST_ID:
			continue
		var ghost: PlayerController = _net_arena.ghosts[id]
		if not is_instance_valid(ghost):
			continue
		_saw_host_ghost = true
		_ghost_error = minf(_ghost_error, ghost.global_position.distance_to(HOST_MARK))

	if _saw_host_ghost and _ghost_error < TOLERANCE and _tick > 120 + WALK_TICKS:
		_finish()

func _finish() -> bool:
	_done = true
	if _is_host:
		_expect(_session.roster.size() >= 2,
				"a client joined (roster %d)" % _session.roster.size())
		_expect(_net_arena.remotes.size() >= 1,
				"and got a character on this machine (%d)" % _net_arena.remotes.size())
		# The one that matters: this character has no local input source, so it
		# can only have moved because commands arrived over the wire and went
		# through the same movement code everything else uses.
		_expect(_client_moved > 2.0,
				"the client's character moved %.1f m from its input" % _client_moved)
	else:
		_expect(_was_connected, "connected to the host")
		_expect(_saw_host_ghost, "a body appeared for the host")
		_expect(_ghost_error < TOLERANCE,
				"and it is where the host says it is (%.2f m off)" % _ghost_error)

	print("\n=== %d checks, %d failed ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	var ok := _failures.is_empty() and _checks > 0
	print("net play test (%s) %s" % ["host" if _is_host else "client",
			"PASSED" if ok else "FAILED"])
	_session.leave()
	quit(0 if ok else 1)
	return true

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % description)
		return
	print("    FAIL %s" % description)
	_failures.append(description)
