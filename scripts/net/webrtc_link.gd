class_name WebRtcLink
extends Node
## One browser-to-browser connection, negotiated by copy and paste.
##
## Exists because the download route is not available to everyone. A managed
## Mac -- a school laptop, say -- can have Terminal locked and unsigned apps
## refused outright, which leaves the browser as the only place the game can
## run at all. So the browser has to be able to do multiplayer.
##
## ENet cannot: browsers have no raw UDP. WebSocket cannot: an HTTPS page may
## not open an insecure connection, and a LAN address cannot hold a
## certificate. WebRTC can, and is the only one that can.
##
## ## Signalling without a signalling server
##
## WebRTC normally needs a server to introduce two peers. That server is the
## exact thing this game does not want -- it would have to be run, paid for and
## kept up, to introduce two people sitting in the same room.
##
## So the introduction is done by hand. The host produces a blob, sends it to
## the other player however they already talk to each other, and pastes the
## reply back. Three copy-pastes, no infrastructure, and it works anywhere two
## browsers can reach each other.
##
## The blob is the offer or answer plus every ICE candidate, deflated and
## base64'd. Candidates are bundled rather than trickled because there is no
## channel to trickle them down -- this is the whole reason the exchange has
## two rounds instead of one.

## Emitted once a blob is ready to hand over.
signal blob_ready(blob: String)
signal connected()
signal failed(reason: String)

## How long to collect ICE candidates before sealing the blob.
##
## There is no way to trickle them later, so this window is the entire
## opportunity to gather. On a LAN host candidates appear almost immediately;
## the wait is generous because a blob missing a candidate produces a
## connection that silently never completes.
const GATHER_SECONDS := 1.5

## Prefix so a blob pasted into the wrong box is rejected with a sentence
## rather than a stack trace.
const MAGIC := "BFPS1:"

var connection: WebRTCPeerConnection

var _sdp_type := ""
var _sdp := ""
var _candidates: Array = []
var _gather_left := 0.0
var _sealed := false
var _sealing := false

func _init() -> void:
	# Runs while the tree is paused, because that is exactly when it has work to
	# do: the lobby pauses the game, and the whole negotiation happens with the
	# lobby open. Left pausable, poll() never runs, no offer is ever produced,
	# and the panel sits there saying "working out your code" forever.
	process_mode = Node.PROCESS_MODE_ALWAYS
	connection = WebRTCPeerConnection.new()

## Get the connection ready, but do not negotiate yet.
##
## Deliberately separate from [method begin_offer]. WebRTCMultiplayerPeer only
## accepts a connection that is still in its initial state, and creating an
## offer moves it out of that state -- so an offer made before the peer is
## added is rejected with an invalid-parameter error and no session at all.
## Splitting the two makes the required order impossible to get wrong.
func open() -> bool:
	# No STUN and no TURN. Both exist to find a route across the internet, and
	# this only ever has to cross a living room -- host candidates are enough,
	# and asking a public STUN server for help would be one more thing that can
	# be down or blocked.
	var error := connection.initialize({"iceServers": []})
	if error != OK:
		failed.emit("This browser would not start a WebRTC connection (error %d)." % error)
		return false
	connection.session_description_created.connect(_on_session_description)
	connection.ice_candidate_created.connect(_on_ice_candidate)
	return true

## Host only, and only once the peer is in the mesh.
func begin_offer() -> void:
	connection.create_offer()

## Take the other side's blob. The host calls this with the answer; the joiner
## calls it with the offer, which makes their browser produce an answer.
func accept_blob(blob: String) -> bool:
	var decoded := decode(blob)
	if decoded.is_empty():
		failed.emit("That does not look like a game code. Copy the whole thing, "
				+ "including the BFPS1: at the start.")
		return false
	var error := connection.set_remote_description(
			String(decoded["type"]), String(decoded["sdp"]))
	if error != OK:
		failed.emit("That code was not usable (error %d). It may be from an "
				% error + "older version, or only half copied.")
		return false
	for entry in decoded["candidates"]:
		if entry is Array and (entry as Array).size() == 3:
			connection.add_ice_candidate(String(entry[0]), int(entry[1]), String(entry[2]))
	return true

func _process(delta: float) -> void:
	if connection == null:
		return
	connection.poll()
	if not _sealing or _sealed:
		return
	_gather_left -= delta
	if _gather_left <= 0.0:
		_seal()

func _on_session_description(type: String, sdp: String) -> void:
	_sdp_type = type
	_sdp = sdp
	# Set locally straight away, which is what starts candidate gathering. The
	# blob is sealed a moment later, once they have arrived.
	connection.set_local_description(type, sdp)
	_sealing = true
	_gather_left = GATHER_SECONDS

func _on_ice_candidate(media: String, index: int, name: String) -> void:
	if _sealed:
		return
	_candidates.append([media, index, name])

func _seal() -> void:
	_sealed = true
	blob_ready.emit(encode(_sdp_type, _sdp, _candidates))

# --- blob format ------------------------------------------------------------

static func encode(type: String, sdp: String, candidates: Array) -> String:
	var payload := {"type": type, "sdp": sdp, "candidates": candidates}
	var raw := JSON.stringify(payload).to_utf8_buffer()
	# Deflated before base64 because SDP is extremely repetitive text, and the
	# difference is between a paste somebody will do and one they will not.
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return MAGIC + Marshalls.raw_to_base64(packed) + ":" + str(raw.size())

## Returns {} if the blob is not one of ours or does not survive the round trip.
static func decode(blob: String) -> Dictionary:
	var cleaned := blob.strip_edges()
	if not cleaned.begins_with(MAGIC):
		return {}
	var body := cleaned.substr(MAGIC.length())
	var split := body.rfind(":")
	if split < 0:
		return {}
	# The original size travels with the blob: the deflate decoder needs it,
	# and a wrong one is also a cheap check that the paste was not truncated,
	# which is the single most likely thing to go wrong here.
	var size := int(body.substr(split + 1))
	var encoded := body.substr(0, split)
	# Checked before handing it over rather than after. Godot's base64 decoder
	# logs an engine error on bad input, which in a browser means red text in
	# the console for what is really just a mistyped paste.
	if encoded.length() % 4 != 0:
		return {}
	for character in encoded:
		if not (character.is_valid_identifier() or character.is_valid_int()
				or character in "+/="):
			return {}
	var packed := Marshalls.base64_to_raw(encoded)
	if packed.is_empty() or size <= 0 or size > 1 << 20:
		return {}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != size:
		return {}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	var out: Dictionary = parsed
	if not out.has("type") or not out.has("sdp") or not out.has("candidates"):
		return {}
	if not out["candidates"] is Array:
		return {}
	return out
