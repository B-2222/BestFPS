class_name WeaponResource
extends Resource
## A weapon, as data.
##
## Same reasoning as [PlayerConfig]: a new weapon should be a new .tres file and
## a model, not a new class. One runtime implementation ([WeaponRuntime] plus
## [WeaponController]) reads all of these, so "rifle" and "shotgun" differ only
## in numbers -- which also means they cannot drift apart in behaviour, and a
## fix to reloading fixes it for every weapon at once.
##
## Times are in seconds and converted to ticks at load; see
## [method WeaponController.seconds_to_ticks] for why nothing here is compared
## against a wall clock.

@export_group("Identity")
@export var id: StringName = &"rifle"
@export var display_name: String = "Rifle"
## Slot the weapon occupies, selected with the 1-4 keys.
@export var slot: int = 1

## Which placeholder viewmodel to build, and how it reloads. Presentation
## keyed off the weapon rather than hardcoded, so a new weapon stays a resource
## plus a shape entry rather than a code change.
@export var view_shape: StringName = &"rifle"
## &"magazine" drops and swaps a mag; &"pump" cycles the handguard.
@export var reload_style: StringName = &"magazine"

@export_group("Firing")
## Held trigger keeps firing. False means one shot per press.
@export var automatic: bool = true
@export var rounds_per_minute: float = 600.0
## Damage per pellet before hitbox multiplier and distance falloff.
@export var damage: float = 22.0
## Applied instead of the hitbox multiplier on a head hit, so each weapon can
## set its own reward for precision -- a sniper's headshot should mean more
## than a shotgun pellet's.
@export var headshot_multiplier: float = 2.2
## Pellets per shot. 1 for everything except shotguns.
@export var pellets: int = 1
@export var max_range: float = 200.0

@export_group("Damage falloff")
## Full damage until this distance, scaling down to
## [member falloff_min_multiplier] at [member falloff_end]. This is the main
## dial that gives weapons their engagement range.
@export var falloff_start: float = 30.0
@export var falloff_end: float = 70.0
@export_range(0.0, 1.0, 0.01) var falloff_min_multiplier: float = 0.55

@export_group("Accuracy")
## Cone half-angle in degrees while standing still and not firing.
@export var spread_min: float = 0.25
@export var spread_max: float = 4.0
## Added per shot, so sustained fire degrades accuracy.
@export var spread_per_shot: float = 0.55
## Degrees recovered per second once you stop firing.
@export var spread_recovery: float = 6.0
## Extra spread at full sprint speed, blended in by how fast you are moving.
@export var spread_moving: float = 2.0
## Multiplier on total spread while aiming down sights.
@export_range(0.0, 1.0, 0.01) var spread_aim_multiplier: float = 0.35

@export_group("Recoil")
## Per-shot view kick in degrees: x = horizontal, y = vertical (positive is up).
## An authored pattern rather than random spray, so it can be learned and
## countered -- that is the difference between recoil that rewards practice and
## recoil that just adds noise. Past the end of the array the last entry repeats.
## Roughly 2.1 degrees of climb across a ten-round burst, and under half a
## degree sideways. Tuned down from twice this after playtesting: the shape was
## right but the magnitude assumed a mouse, and a trackpad cannot drag the view
## back down fast enough to fight it. Recoil you cannot counter is not
## difficulty, it is just a worse gun.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 0.20), Vector2(-0.05, 0.22), Vector2(0.07, 0.24),
	Vector2(-0.09, 0.25), Vector2(0.12, 0.24), Vector2(0.15, 0.22),
	Vector2(-0.14, 0.20), Vector2(-0.16, 0.18), Vector2(0.13, 0.16),
	Vector2(0.11, 0.14),
])
## Degrees per second the view drifts back after the delay below.
@export var recoil_recovery: float = 11.0
## Grace period after the last shot before recovery starts, so tapping does not
## fight the player's own compensation.
@export var recoil_recovery_delay: float = 0.10

@export_group("Ammo and timing")
@export var magazine_size: int = 30
@export var reserve_ammo: int = 120
@export var reload_seconds: float = 2.1
@export var equip_seconds: float = 0.45

@export_group("Handling")
## Movement speed multiplier while this weapon is held.
@export_range(0.1, 1.0, 0.01) var move_speed_multiplier: float = 1.0
## Movement speed multiplier while aiming down sights.
@export_range(0.1, 1.0, 0.01) var aim_move_multiplier: float = 0.55
## FOV subtracted from the base while aiming.
@export var aim_fov_reduction: float = 18.0
## True for a magnified optic. Sighting one hides the weapon and replaces the
## view with a scope picture, rather than shoving the receiver in front of the
## player's face and calling it aiming.
@export var has_scope: bool = false

func seconds_per_shot() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)

## Kick for the nth consecutive shot, clamping to the last authored entry.
func recoil_for_shot(index: int) -> Vector2:
	if recoil_pattern.is_empty():
		return Vector2.ZERO
	return recoil_pattern[mini(index, recoil_pattern.size() - 1)]
