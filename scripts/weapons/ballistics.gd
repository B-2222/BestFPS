class_name Ballistics
extends RefCounted
## Pure functions shared by every weapon. No state, no nodes -- so the server
## can run exactly the same maths in Milestone 5 without a scene tree.

## Physics layers a bullet can stop on: 1 (world) and 4 (hitbox).
##
## Character bodies -- layer 2 (player) and 3 (bot) -- are deliberately absent.
## Shots pass straight through the movement hull and only register on hitboxes,
## which is what lets hitbox shape be tuned for fair hit registration without
## also changing how characters collide and move.
const TRACE_MASK := 1 | 8

## Deterministic RNG for one pellet of one shot.
##
## Seeded from the command tick and a salt rather than left free-running,
## because in Milestone 5 the client and the server each compute this shot
## independently and must agree on where the pellets went. A shared clock or a
## global RNG would desync on the first dropped packet.
static func make_rng(tick: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(tick, salt))
	return rng

## Deviate [param forward] within a cone of half-angle [param spread_rad].
##
## sqrt() on the random radius makes the distribution uniform over the cone's
## area. Without it the pellets bunch toward the centre, which reads as "the
## spread number is lying to me" when a shotgun's outer pellets almost never
## appear.
static func apply_spread(forward: Vector3, spread_rad: float,
		rng: RandomNumberGenerator) -> Vector3:
	if spread_rad <= 0.0:
		return forward
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(reference).normalized()
	var up := right.cross(forward).normalized()
	var angle := sqrt(rng.randf()) * spread_rad
	var azimuth := rng.randf() * TAU
	var offset := (right * cos(azimuth) + up * sin(azimuth)) * tan(angle)
	return (forward + offset).normalized()

## Damage scale at a given distance. Full damage up to falloff_start, ramping
## linearly to falloff_min_multiplier at falloff_end.
static func falloff(distance: float, weapon: WeaponResource) -> float:
	if distance <= weapon.falloff_start:
		return 1.0
	if distance >= weapon.falloff_end:
		return weapon.falloff_min_multiplier
	var span := maxf(weapon.falloff_end - weapon.falloff_start, 0.001)
	return lerpf(1.0, weapon.falloff_min_multiplier,
			(distance - weapon.falloff_start) / span)

## Final damage for one pellet, before it is handed to [Health].
static func resolve_damage(weapon: WeaponResource, hitbox: Hitbox,
		distance: float) -> float:
	var multiplier := weapon.headshot_multiplier if hitbox.is_headshot() \
			else hitbox.damage_multiplier
	return weapon.damage * multiplier * falloff(distance, weapon)
