class_name Hitbox
extends Area3D
## A shootable region on a character.
##
## Separate from the character's collision hull on purpose, and on its own
## physics layer (4, "hitbox"). Weapon traces mask against layer 4 only and pass
## straight through layer 2 ("player") and layer 3 ("bot"), which means:
##
## - Hitboxes can be tuned for *fairness* -- a head slightly larger than the
##   model, limbs slightly smaller -- with no effect on how the character moves
##   or collides. If shots hit the movement hull, every hit-registration tweak
##   would be a movement change too.
## - Milestone 5's lag compensation can move hitboxes back in time without
##   teleporting the character's actual body.

## Identifies the region: &"head", &"body", &"limb". Carried into [DamageInfo]
## so the HUD can tell a headshot apart without re-deriving it.
@export var hitbox_id: StringName = &"body"

## Multiplier applied to incoming damage. This is where time-to-kill is
## actually decided -- weapon damage sets the baseline, hitboxes set the reward
## for aiming well.
@export var damage_multiplier: float = 1.0

## Owning [Health]. Resolved by searching upward so a hitbox can sit anywhere in
## a character's hierarchy without wiring a path by hand.
var health: Health = null

func _ready() -> void:
	collision_layer = 8   # layer 4: hitbox
	collision_mask = 0    # hitboxes never need to detect anything themselves
	monitoring = false    # traced against, not polled
	monitorable = true
	health = _find_health()
	if health == null:
		push_warning("Hitbox '%s' has no Health ancestor; it will absorb shots silently." % name)

func is_headshot() -> bool:
	return hitbox_id == &"head"

func _find_health() -> Health:
	var node := get_parent()
	while node != null:
		for child in node.get_children():
			if child is Health:
				return child
		node = node.get_parent()
	return null
