class_name WeaponRuntime
extends RefCounted
## Mutable per-weapon state: ammo, timers, and where we are in the recoil and
## spread curves.
##
## Split from [WeaponResource] because the resource is shared -- every player
## and bot carrying a rifle reads the same .tres -- while this is per-carrier.
## Writing ammo into the resource would drain everyone's magazine at once.
##
## All timers are integer tick counts, never seconds. A replayed command has to
## produce the same result as the original, and wall-clock time cannot be
## replayed.

## Named Phase, not State: `State` is already a global class_name (the movement
## FSM base), and GDScript resolves a bare `State` to that global class rather
## than to a local enum -- which fails with a type mismatch that does not
## mention shadowing at all.
enum Phase { READY, RELOADING, EQUIPPING }

var resource: WeaponResource
var magazine: int = 0
var reserve: int = 0
var phase: Phase = Phase.READY
## Ticks left in RELOADING or EQUIPPING.
var state_ticks: int = 0
## Ticks until the weapon may fire again.
var cooldown_ticks: int = 0
## Consecutive shots, indexing the recoil pattern and driving spread growth.
## Reset when the player stops firing long enough to recover.
var shot_index: int = 0
## Current cone half-angle in degrees, before movement and aim modifiers.
var spread: float = 0.0
## Seconds since the last shot, for recoil and spread recovery delays.
var since_last_shot: float = 999.0

func _init(weapon: WeaponResource) -> void:
	resource = weapon
	magazine = weapon.magazine_size
	reserve = weapon.reserve_ammo
	spread = weapon.spread_min

func can_fire() -> bool:
	return phase == Phase.READY and cooldown_ticks <= 0 and magazine > 0

func needs_reload() -> bool:
	return magazine <= 0

func can_reload() -> bool:
	return phase == Phase.READY and reserve > 0 and magazine < resource.magazine_size

func total_ammo() -> int:
	return magazine + reserve
