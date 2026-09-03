class_name NetSession
extends Node
## Owns the connection and the lobby roster. Knows nothing about the game.
##
## Kept apart from anything that spawns or simulates a character on purpose:
## this file is about who is connected, and the rules for that do not change
## when the game does. It is also the only file that touches
## [MultiplayerAPI] directly, so "how do we talk to each other" is one place.
##
## ## Transport
##
## ENet over UDP, which is Godot's default high-level peer and the right answer
## for a LAN: no relay, no signalling server, no account, no internet. The host
## opens a port and hands out a [JoinCode] containing its own LAN address; a
## client decodes that and connects straight to it.
##
## **This does not work from the browser build.** Browsers cannot open raw UDP
## sockets, and the WebSocket alternative needs the page and the socket to
## agree on TLS -- a page served over HTTPS from GitHub Pages may not open an
## insecure ws:// connection to a LAN address, and a LAN address cannot have a
## certificate. So multiplayer is a desktop-build feature, and the browser
## build stays single-player against bots. See docs/networking-decision.md.

signal link_changed(link: Link)
## The roster changed: someone joined, left, renamed, or readied up.
signal lobby_changed()
## Something went wrong in a way the player has to see.
signal failed(reason: String)
## A browser-to-browser code is ready to hand to the other player.
signal blob_ready(blob: String)

## Named Link, not State: `State` is already a global class_name in this
## project -- the movement state base class -- and a local enum of that name is
## silently shadowed by it, producing type errors that point at every use site
## and never at the declaration. Third time this trap has been hit here; see
## WeaponRuntime.Phase for the first.
enum Link { OFFLINE, HOSTING, JOINING, CONNECTED }

const DEFAULT_PORT := 24565
## Including the host. Eight is well past what this arena is sized for and
## still comfortable for ENet on a LAN.
const MAX_PLAYERS := 8
## Give up on a connection attempt after this. ENet will happily sit in
## "connecting" forever against an address nobody is listening on, which reads
## to the player as the game having frozen.
const CONNECT_TIMEOUT := 8.0

const HOST_ID := 1
## The other player in a browser-to-browser game. Two-player only for now: a
## mesh of three or more needs every pair introduced to every other pair, which
## is three copy-pastes each and not something anyone would do.
const GUEST_ID := 2

var link: Link = Link.OFFLINE
## The code to read out. Empty unless hosting.
var join_code: String = ""
## peer id -> {"name": String, "bot": bool}. Mirrored on every peer.
var roster: Dictionary = {}
var local_name: String = "Player"

var _connect_timer: float = 0.0
var _link: WebRtcLink = null

var _signals_ready: bool = false

func _init() -> void:
	# Same reason as WebRtcLink: connecting, timing out and negotiating all
	# happen with the lobby open, and the lobby pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Connect on first use rather than in _ready().
##
## Node.multiplayer resolves through the tree, and it is still null while the
## tree is being brought up -- an autoload's _ready() can run early enough to
## see nothing there. Connecting lazily is the same fix this project has needed
## for CameraRig, ViewModel, AudioDirector and BotBrain, for the same reason:
## something below asked for something above before it existed.
func _ensure_signals() -> bool:
	if _signals_ready:
		return true
	if multiplayer == null:
		return false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_signals_ready = true
	return true

func _process(delta: float) -> void:
	_ensure_signals()
	if link != Link.JOINING:
		return
	_connect_timer -= delta
	if _connect_timer <= 0.0:
		leave()
		failed.emit("No answer from that code. Check the host is still up and "
				+ "that you are both on the same network.")

func is_host() -> bool:
	return link == Link.HOSTING

## True when this peer decides things: the host, or a solo session with no
## networking at all. Everything that must not be simulated twice asks this.
func is_authority() -> bool:
	return link == Link.OFFLINE or link == Link.HOSTING

## Open the port and start a lobby.
##
## Opening the port and working out what address to advertise are separate
## steps, and only the first can fail the host. A machine can have no private
## address at all -- a container, an odd VPN setup, ethernet unplugged -- and
## refusing to host there is wrong: the game is up and reachable by anyone who
## knows the address, there is just no code to hand out. [member join_code] is
## empty in that case and the lobby says so, rather than the button doing
## nothing and the player never learning why.
func host(player_name: String = "") -> bool:
	if not _ensure_signals():
		failed.emit("Networking is not ready yet. Try again in a moment.")
		return false
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(DEFAULT_PORT, MAX_PLAYERS - 1)
	if error != OK:
		failed.emit("Could not open port %d (error %d). Another copy of the "
				% [DEFAULT_PORT, error] + "game may already be hosting.")
		return false

	multiplayer.multiplayer_peer = peer
	var address := JoinCode.local_address()
	join_code = JoinCode.encode(address, DEFAULT_PORT) if address != "" else ""
	local_name = player_name if player_name != "" else "Host"
	roster = {HOST_ID: {"name": local_name, "bot": false}}
	_set_link(Link.HOSTING)
	lobby_changed.emit()
	# Deliberately not emitted as a failure. Hosting succeeded; there is just
	# no code to hand out, and the lobby already says exactly that where the
	# code would be. Routing it through the error channel made an
	# informational message look like something had gone wrong.
	return true

## A code for an address the player typed in themselves, for when discovery
## could not find one.
static func code_for(address: String, port: int = DEFAULT_PORT) -> String:
	return JoinCode.encode(address, port)

# --- browser to browser -----------------------------------------------------
#
# The same lobby and the same game on a different transport. Everything above
# this file -- the roster, NetArena, the snapshots, the input replication --
# goes through MultiplayerAPI and cannot tell the difference, which is the
# whole reason a second transport was affordable at all.

## Start a browser-hosted game. The offer arrives on [signal blob_ready].
func host_p2p(player_name: String = "") -> bool:
	if not _ensure_signals():
		failed.emit("Networking is not ready yet. Try again in a moment.")
		return false
	leave()
	if not _start_link():
		return false
	var mesh := WebRTCMultiplayerPeer.new()
	if mesh.create_mesh(HOST_ID) != OK:
		failed.emit("This browser would not start a peer-to-peer session.")
		return false
	if mesh.add_peer(_link.connection, GUEST_ID) != OK:
		failed.emit("This browser would not accept a peer.")
		return false
	multiplayer.multiplayer_peer = mesh
	local_name = player_name if player_name != "" else "Host"
	roster = {HOST_ID: {"name": local_name, "bot": false}}
	join_code = ""
	_set_link(Link.HOSTING)
	lobby_changed.emit()
	# Only now, with the peer in the mesh: see WebRtcLink.open().
	_link.begin_offer()
	return true

## Join a browser-hosted game from the host's offer. The answer to send back
## arrives on [signal blob_ready].
func join_p2p(offer: String, player_name: String = "") -> bool:
	if not _ensure_signals():
		failed.emit("Networking is not ready yet. Try again in a moment.")
		return false
	leave()
	if not _start_link():
		return false
	var mesh := WebRTCMultiplayerPeer.new()
	if mesh.create_mesh(GUEST_ID) != OK:
		failed.emit("This browser would not start a peer-to-peer session.")
		return false
	if mesh.add_peer(_link.connection, HOST_ID) != OK:
		failed.emit("This browser would not accept a peer.")
		return false
	multiplayer.multiplayer_peer = mesh
	local_name = player_name if player_name != "" else "Player"
	_set_link(Link.JOINING)
	# Setting the offer is what makes this browser produce an answer, which
	# comes back through blob_ready a second or so later.
	if not _link.accept_blob(offer):
		leave()
		return false
	# No timeout on this path. There is nothing to time out against -- the wait
	# is on a human copying a blob into a chat window, which can take as long
	# as it takes.
	_connect_timer = INF
	return true

## Host only: take the answer the other player sent back.
func accept_answer(answer: String) -> bool:
	if _link == null:
		failed.emit("Host a game first, then paste their reply.")
		return false
	return _link.accept_blob(answer)

func _start_link() -> bool:
	_clear_link()
	_link = WebRtcLink.new()
	_link.name = "Link"
	add_child(_link)
	_link.blob_ready.connect(func(blob: String) -> void: blob_ready.emit(blob))
	_link.failed.connect(func(reason: String) -> void: failed.emit(reason))
	if not _link.open():
		_clear_link()
		return false
	return true

func _clear_link() -> void:
	if _link != null and is_instance_valid(_link):
		_link.queue_free()
	_link = null

func join(code: String, player_name: String = "") -> bool:
	if not _ensure_signals():
		failed.emit("Networking is not ready yet. Try again in a moment.")
		return false
	var parsed := JoinCode.decode(code)
	if not parsed["ok"]:
		failed.emit(parsed["error"])
		return false
	leave()

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(parsed["ip"], parsed["port"])
	if error != OK:
		failed.emit("Could not reach %s (error %d)." % [parsed["ip"], error])
		return false

	multiplayer.multiplayer_peer = peer
	local_name = player_name if player_name != "" else "Player"
	_connect_timer = CONNECT_TIMEOUT
	_set_link(Link.JOINING)
	return true

func leave() -> void:
	if multiplayer != null and multiplayer.multiplayer_peer != null \
			and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	if multiplayer != null:
		multiplayer.multiplayer_peer = null
	_clear_link()
	roster.clear()
	join_code = ""
	_set_link(Link.OFFLINE)
	lobby_changed.emit()

## Everyone in the lobby, host first, then joiners in id order. Sorted so every
## peer renders the same list in the same order without having to agree on one.
func ordered_peers() -> Array:
	var ids := roster.keys()
	ids.sort()
	return ids

func display_name(peer_id: int) -> String:
	var entry: Dictionary = roster.get(peer_id, {})
	return String(entry.get("name", "Player %d" % peer_id))

# --- connection callbacks ---------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		# A browser session is a WebRTC *mesh*, and a mesh has no server, so
		# connected_to_server never fires on the joiner -- it only ever learns
		# it is in by seeing the host appear. Without this the joiner sits on
		# CONNECTING forever, never sends its name, and the lobby shows two
		# players who cannot see each other.
		if peer_id == HOST_ID and link == Link.JOINING:
			_on_connected()
		return
	# The host owns the roster. A joiner is added here and the whole list is
	# pushed back out, rather than each peer maintaining its own copy from
	# connection events -- with several people joining at once those events
	# arrive in different orders on different machines.
	roster[peer_id] = {"name": "Player %d" % peer_id, "bot": false}
	_push_roster()
	lobby_changed.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	roster.erase(peer_id)
	_push_roster()
	lobby_changed.emit()

func _on_connected() -> void:
	_set_link(Link.CONNECTED)
	_claim_name.rpc_id(HOST_ID, local_name)

func _on_connection_failed() -> void:
	leave()
	failed.emit("That code did not connect. Check it and that you are both on "
			+ "the same network.")

func _on_server_disconnected() -> void:
	leave()
	failed.emit("The host closed the game.")

# --- roster replication -----------------------------------------------------

func _push_roster() -> void:
	_receive_roster.rpc(roster)

## Reliable, not unreliable: a dropped roster update leaves someone's lobby
## permanently wrong, and it is sent once per join rather than per tick.
@rpc("authority", "call_remote", "reliable")
func _receive_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _claim_name(wanted: String) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not roster.has(peer_id):
		return
	# Trimmed and capped here rather than trusting the sender. It is only a
	# display name, but it is the first piece of data this game accepts from
	# somebody else's machine, and the habit is worth forming on the easy case.
	var cleaned := wanted.strip_edges().substr(0, 20)
	roster[peer_id]["name"] = cleaned if cleaned != "" else "Player %d" % peer_id
	_push_roster()
	lobby_changed.emit()

func _set_link(new_link: Link) -> void:
	if link == new_link:
		return
	link = new_link
	link_changed.emit(link)
