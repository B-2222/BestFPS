class_name DamageInfo
extends RefCounted
## One resolved damage event, passed whole rather than as loose arguments.
##
## A struct because every consumer wants a different slice of it: [Health] wants
## the amount, the HUD wants to know if it was a headshot, the kill feed
## (Milestone 6) wants attacker and weapon, and the server (Milestone 5) wants
## the tick to validate against. Adding a field must not mean editing every
## signature in between.

var amount: float = 0.0
## Attacker's [Health]-owning node. Null for world damage such as fall damage.
var source: Node = null
## Who was hit. Recorded so a kill feed does not have to work backwards from a
## hitbox to a character, and so a future scoreboard can tell a kill from a
## suicide without a second lookup.
var victim: Node = null
var weapon_id: StringName = &""
## Which hitbox resolved this, e.g. &"head". Drives the multiplier and the
## headshot hit marker.
var hitbox_id: StringName = &""
var is_headshot: bool = false
## World-space impact point and surface normal, for effects and decals.
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
## Metres from muzzle to impact. Recorded even after falloff is applied so the
## HUD and any later damage log can explain *why* a shot did what it did.
var distance: float = 0.0
## Simulation tick the shot was fired on. The key the server rewinds to.
var tick: int = 0
