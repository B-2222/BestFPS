class_name JoinCode
extends RefCounted
## The short string one player reads out and the other types in.
##
## It is just an address in disguise: four bytes of IPv4 and two of port,
## 48 bits, packed into ten characters. Nothing is looked up and no server is
## contacted -- the code *is* the connection details, which is what makes this
## work on a LAN with no infrastructure at all.
##
## The alphabet deliberately omits 0, O, 1 and I. Codes get read out loud
## across a room, and "zero or oh" is the failure mode that makes people give
## up on join codes.

const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const LENGTH := 10
## Where the hyphen goes when displaying. Purely cosmetic; decode ignores it.
const GROUP := 5

static func encode(ip: String, port: int) -> String:
	var octets := ip.split(".")
	if octets.size() != 4:
		return ""
	var value := 0
	for octet in octets:
		value = (value << 8) | (int(octet) & 0xFF)
	value = (value << 16) | (port & 0xFFFF)

	var out := ""
	for i in LENGTH:
		# Most significant group first, so codes for nearby addresses differ
		# at the end rather than the beginning -- easier to spot a typo.
		var shift := (LENGTH - 1 - i) * 5
		out += ALPHABET[(value >> shift) & 0x1F]
	return "%s-%s" % [out.substr(0, GROUP), out.substr(GROUP)]

## Returns {"ok": bool, "ip": String, "port": int, "error": String}.
static func decode(code: String) -> Dictionary:
	var cleaned := ""
	for character in code.to_upper():
		if character == "-" or character == " ":
			continue
		# Deliberately no "did you mean" correction table. Every plausible
		# substitution here maps one valid code onto a *different* valid code,
		# so a silent fix would connect somebody to the wrong machine and look
		# like a network fault. Rejecting is worse UX and much better
		# behaviour.
		if ALPHABET.find(character) < 0:
			return _fail("'%s' is not in a join code. They use %s only."
					% [character, ALPHABET])
		cleaned += character
	if cleaned.length() != LENGTH:
		return _fail("A join code is %d characters; that one is %d."
				% [LENGTH, cleaned.length()])

	var value := 0
	for character in cleaned:
		value = (value << 5) | ALPHABET.find(character)

	var port := value & 0xFFFF
	var address := value >> 16
	var ip := "%d.%d.%d.%d" % [(address >> 24) & 0xFF, (address >> 16) & 0xFF,
			(address >> 8) & 0xFF, address & 0xFF]
	if port == 0:
		return _fail("That code has no port in it.")
	return {"ok": true, "ip": ip, "port": port, "error": ""}

## The address to put in a join code: this machine's own LAN address.
##
## Picks a private one on purpose. A machine typically has several -- loopback,
## a docker bridge, a VPN -- and handing out the wrong one produces a code that
## looks right and never connects, which is the worst kind of bug to debug over
## a phone call.
static func local_address() -> String:
	var best := ""
	for address in IP.get_local_addresses():
		if not _is_private_ipv4(address):
			continue
		# 192.168.x is the overwhelmingly common home LAN, so prefer it over a
		# 10.x or 172.16-31.x that is more likely to be a VPN or a container.
		if address.begins_with("192.168."):
			return address
		if best == "":
			best = address
	return best

static func _is_private_ipv4(address: String) -> bool:
	var octets := address.split(".")
	if octets.size() != 4:
		return false
	for octet in octets:
		if not octet.is_valid_int():
			return false
	var a := int(octets[0])
	var b := int(octets[1])
	if a == 10:
		return true
	if a == 192 and b == 168:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	return false

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "ip": "", "port": 0, "error": reason}
