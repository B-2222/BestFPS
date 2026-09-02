class_name CharacterHitboxes
extends RefCounted
## The standard head/body/legs hitbox layout, in one place.
##
## Players, bots and practice dummies all use it, which is the point: a shot
## that would hit a dummy in the head has to hit a bot in the head too. Two
## copies of these numbers would drift, and the drift would show up as
## "shooting bots feels different to shooting the range" long after the cause
## was forgotten.
##
## Sized to the 1.8 m player hull. Multipliers reward precision: legs are worth
## less, and the head is handled by the weapon's own headshot multiplier so
## each weapon decides what precision is worth.

## id, size, centre height, damage multiplier
const PARTS := [
	[&"legs", Vector3(0.50, 0.90, 0.34), 0.45, 0.80],
	[&"body", Vector3(0.62, 0.66, 0.34), 1.23, 1.00],
	[&"head", Vector3(0.28, 0.28, 0.28), 1.70, 1.00],
]

## Attach a full hitbox set to [param host]. With [param make_meshes] the parts
## are also visible, which bots and dummies want and a first-person player
## does not.
static func build(host: Node3D, make_meshes: bool) -> Array[Hitbox]:
	var built: Array[Hitbox] = []
	for part in PARTS:
		var id: StringName = part[0]
		var hitbox := Hitbox.new()
		hitbox.name = String(id).capitalize() + "Hitbox"
		hitbox.hitbox_id = id
		hitbox.damage_multiplier = part[3]
		hitbox.position = Vector3(0.0, part[2], 0.0)
		host.add_child(hitbox)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[1]
		shape.shape = box
		hitbox.add_child(shape)

		if make_meshes:
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var box_mesh := BoxMesh.new()
			box_mesh.size = part[1]
			mesh.mesh = box_mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = base_color(id)
			material.roughness = 0.8
			mesh.material_override = material
			hitbox.add_child(mesh)
			if id == &"head":
				hitbox.add_child(make_visor(part[1]))

		built.append(hitbox)
	return built

## Head is the odd one out on purpose: it marks where the reward is.
static func base_color(id: StringName) -> Color:
	return Color(0.92, 0.55, 0.20) if id == &"head" else Color(0.72, 0.74, 0.80)

## A dark band across the front of the head.
##
## Purely so you can tell which way a character is looking. Without it two
## identical boxes give no facing cue at all, and "has it seen me yet?" is the
## single most important thing to be able to read about a bot -- it is what
## makes flanking a decision rather than a coin flip.
static func make_visor(head_size: Vector3) -> MeshInstance3D:
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(head_size.x * 0.82, head_size.y * 0.34, 0.03)
	visor.mesh = mesh
	# -Z is forward in Godot, and the head box is centred on the origin, so
	# half its depth plus a sliver puts the band just proud of the face.
	visor.position = Vector3(0.0, head_size.y * 0.06, -(head_size.z * 0.5 + 0.015))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.06, 0.07, 0.10)
	material.roughness = 0.25
	material.metallic = 0.4
	visor.material_override = material
	return visor
