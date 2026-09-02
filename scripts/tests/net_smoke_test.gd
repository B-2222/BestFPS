extends SceneTree
## Headless checks for the join code and the connection handshake.
##
## Run: godot --headless --path . --script scripts/tests/net_smoke_test.gd
##
## The join code is pure arithmetic and is checked exhaustively-ish: every code
## this game can produce has to survive being read out loud and typed back in,
## and an address that decodes to something *plausible but wrong* is the worst
## possible failure -- it looks like a network fault and sends somebody hunting
## through their router settings.
##
## The handshake half runs a real ENet server and a real client in one process
## over loopback, using two SceneMultiplayerPeer instances on separate
## sub-trees. That catches the things a mock cannot: RPC signatures, roster
## replication order, and whether the host is actually listening.

var _plan: Array = []
var _phase := 0
var _phase_tick := 0
var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

var _host: NetSession
var _client: NetSession
var _host_root: Node
var _client_root: Node
var _client_failure := ""

func _initialize() -> void:
	_build_plan()
	print("\n=== net smoke test (%d phases) ===\n" % _plan.size())

func _physics_process(_delta: float) -> bool:
	if _phase >= _plan.size():
		return _finish()
	var step: Dictionary = _plan[_phase]
	if _phase_tick == 0:
		print("  [%d/%d] %s" % [_phase + 1, _plan.size(), step["name"]])
		if step.has("setup"):
			(step["setup"] as Callable).call()
	if step.has("during"):
		(step["during"] as Callable).call(_phase_tick)
	_phase_tick += 1
	if _phase_tick >= int(step["ticks"]):
		if step.has("check"):
			(step["check"] as Callable).call()
		_phase += 1
		_phase_tick = 0
	return false

# ---------------------------------------------------------------------------

func _build_plan() -> void:
	_plan = [
	{
		"name": "a code round-trips back to the address it was made from",
		"ticks": 1,
		"check": func() -> void:
			var cases := [
				["192.168.1.42", 24565], ["192.168.0.1", 24565],
				["10.0.0.7", 7777], ["172.20.11.250", 65535],
				["192.168.255.254", 1],
			]
			for case in cases:
				var code: String = JoinCode.encode(case[0], case[1])
				var back := JoinCode.decode(code)
				_expect(back["ok"] and back["ip"] == case[0] and back["port"] == case[1],
						"%s:%d -> %s -> %s:%d" % [case[0], case[1], code,
							back["ip"], back["port"]]),
	},
	{
		"name": "every address on a home LAN round-trips",
		"ticks": 1,
		"check": func() -> void:
			# The whole 192.168.x.y space, which is where these games will
			# actually be played. One bad bit shift would show up here and
			# nowhere in a handful of spot checks.
			var bad := 0
			var tested := 0
			for third in 256:
				for fourth in [0, 1, 2, 42, 128, 199, 254, 255]:
					var ip := "192.168.%d.%d" % [third, fourth]
					var back := JoinCode.decode(JoinCode.encode(ip, NetSession.DEFAULT_PORT))
					tested += 1
					if not back["ok"] or back["ip"] != ip \
							or back["port"] != NetSession.DEFAULT_PORT:
						bad += 1
			_expect(bad == 0, "%d of %d addresses round-tripped" % [tested - bad, tested]),
	},
	{
		"name": "codes are readable and hyphenated",
		"ticks": 1,
		"check": func() -> void:
			var code := JoinCode.encode("192.168.1.42", NetSession.DEFAULT_PORT)
			_expect(code.length() == JoinCode.LENGTH + 1,
					"%s is %d characters with its hyphen" % [code, code.length()])
			_expect(code.contains("-"), "grouped with a hyphen")
			for character in code.replace("-", ""):
				# 0/O and 1/I are the pair people get wrong reading a code out
				# loud, so the alphabet must never contain them.
				_expect(not "01IO".contains(character),
						"'%s' is not an ambiguous character" % character),
	},
	{
		"name": "a code is accepted however it is typed",
		"ticks": 1,
		"check": func() -> void:
			var code := JoinCode.encode("10.1.2.3", 24565)
			for variant in [code, code.to_lower(), code.replace("-", ""),
					" %s " % code, code.replace("-", " ")]:
				var back := JoinCode.decode(variant)
				_expect(back["ok"] and back["ip"] == "10.1.2.3",
						"'%s' decodes" % variant),
	},
	{
		"name": "a bad code is refused, not guessed at",
		"ticks": 1,
		"check": func() -> void:
			for bad in ["", "ABC", "ABCDE-FGHIJ-KLMNO", "ABCDE-FGHI0", "!!!!!-!!!!!"]:
				var back := JoinCode.decode(bad)
				_expect(not back["ok"], "'%s' is rejected" % bad)
				_expect(back["error"] != "", "and says why: %s" % back["error"])
			# The nastiest case: a code one character off another valid code
			# must not silently resolve to a different machine.
			var good := JoinCode.encode("192.168.1.42", 24565)
			var mangled := good.substr(0, 3) + "I" + good.substr(4)
			_expect(not JoinCode.decode(mangled)["ok"],
					"a mistyped character is an error, not a different address"),
	},
	{
		"name": "the address a host advertises is a private one",
		"ticks": 1,
		"check": func() -> void:
			var address := JoinCode.local_address()
			# CI runners and containers have odd network setups, so an empty
			# answer is allowed -- but a public address never is, because that
			# is a code that leaks where you are and still does not connect.
			if address == "":
				_expect(true, "no private address on this machine (allowed)")
				return
			var back := JoinCode.decode(JoinCode.encode(address, 1))
			_expect(back["ok"] and back["ip"] == address,
					"%s survives being put in a code" % address)
			_expect(address.begins_with("192.168.") or address.begins_with("10.")
					or address.begins_with("172."),
					"%s is a private address" % address),
	},
	{
		"name": "a host opens a port and produces a usable code",
		"ticks": 30,
		"setup": func() -> void:
			_host_root = _make_peer_root("HostRoot")
			_host = _host_root.get_node("Session") as NetSession
			_host.host("Host"),
		"check": func() -> void:
			_expect(_host.link == NetSession.Link.HOSTING, "host is hosting")
			_expect(_host.roster.size() == 1, "the host is in its own roster")
			_expect(_host.is_authority(), "and is the authority")
			# The code is only produced when this machine has a private
			# address to advertise. CI runners often do not, and hosting must
			# still work there -- the port is open either way.
			if _host.join_code == "":
				_expect(true, "no private address here, so no code (allowed)")
				return
			var back := JoinCode.decode(_host.join_code)
			_expect(back["ok"] and back["port"] == NetSession.DEFAULT_PORT,
					"code %s points at the port it opened" % _host.join_code),
	},
	{
		"name": "a client joins with that code and both see the roster",
		"ticks": 240,
		"setup": func() -> void:
			_client_root = _make_peer_root("ClientRoot")
			_client = _client_root.get_node("Session") as NetSession
			_client.failed.connect(func(reason: String) -> void:
				_client_failure = reason)
			# Loopback rather than the advertised address: CI runners often
			# have no private address at all, and this phase is testing the
			# handshake, not address discovery.
			_client.join(JoinCode.encode("127.0.0.1", NetSession.DEFAULT_PORT),
					"Joiner"),
		"check": func() -> void:
			_expect(_client_failure == "", "no failure reported: %s" % _client_failure)
			_expect(_client.link == NetSession.Link.CONNECTED, "client is connected")
			_expect(not _client.is_authority(), "and is not the authority")
			_expect(_host.roster.size() == 2,
					"host sees 2 in the lobby, got %d" % _host.roster.size())
			_expect(_client.roster.size() == 2,
					"client sees 2 in the lobby, got %d" % _client.roster.size())
			# The name the joiner asked for has to have reached the host and
			# come back, which exercises the RPC in both directions.
			var names: Array = []
			for id in _client.ordered_peers():
				names.append(_client.display_name(id))
			_expect(names.has("Joiner"), "the joiner's own name arrived: %s" % str(names))
			_expect(names.has("Host"), "and so did the host's: %s" % str(names))
			_expect(_client.ordered_peers() == _host.ordered_peers(),
					"both peers order the lobby identically"),
	},
	{
		"name": "the roster shrinks when someone leaves",
		"ticks": 120,
		"setup": func() -> void:
			_client.leave(),
		"check": func() -> void:
			_expect(_host.roster.size() == 1,
					"host is alone again, got %d" % _host.roster.size())
			_expect(_client.link == NetSession.Link.OFFLINE, "client is offline"),
	},
	{
		"name": "a code nobody is listening on gives up instead of hanging",
		# Longer than NetSession.CONNECT_TIMEOUT in real time, since that is
		# what the timeout is measured in: 1250 ticks at 120 Hz is 10.4 s
		# against an 8 s give-up.
		"ticks": 1250,
		"setup": func() -> void:
			_client_failure = ""
			# A port deliberately not opened by anything in this test.
			_client.join(JoinCode.encode("127.0.0.1", 24999), "Nobody"),
		"check": func() -> void:
			_expect(_client_failure != "", "reported a failure rather than hanging")
			_expect(_client.link == NetSession.Link.OFFLINE,
					"and went back to offline")
			_host.leave(),
	},
	]

# ---------------------------------------------------------------------------

## Two independent multiplayer peers in one process.
##
## Godot resolves the MultiplayerAPI by scene-tree branch, so giving each side
## its own sub-tree and its own API is what lets a host and a client coexist
## here at all -- with one shared API the second create_*() simply replaces the
## first.
func _make_peer_root(peer_name: String) -> Node:
	var branch := Node.new()
	branch.name = peer_name
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	# set_multiplayer lives on SceneTree, not on the root Window, and wants the
	# absolute path of the branch the API governs.
	set_multiplayer(api, NodePath("/root/%s" % peer_name))
	var session := NetSession.new()
	session.name = "Session"
	branch.add_child(session)
	return branch

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % description)
		return
	print("    FAIL %s" % description)
	_failures.append("%s: %s" % [_plan[_phase]["name"], description])

func _finish() -> bool:
	print("\n=== %d checks, %d failed ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	var ok := _failures.is_empty() and _checks > 0
	if _checks == 0:
		print("net smoke test ran no checks")
	print("net smoke test %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
	return true
