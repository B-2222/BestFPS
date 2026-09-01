class_name CombatFx
extends Node3D
## Short-lived shooting feedback: tracers, impacts, floating damage numbers.
##
## Feedback is not decoration in a shooter -- without a visible tracer and an
## impact mark, a miss and a hit on a distant target look identical, and the
## player cannot tell whether their aim or the spread is at fault. This is the
## cheapest version that answers "where did that bullet actually go".
##
## Materials are cached and shared; only the meshes and transforms are per
## effect, and every effect frees itself.

const TRACER_SECONDS := 0.11
const IMPACT_SECONDS := 0.22
const NUMBER_SECONDS := 0.75

## Bullet holes last this long, fading over the final quarter.
const HOLE_SECONDS := 9.0
## Oldest holes are recycled past this. Without a cap, a held trigger leaves
## six hundred nodes a minute on the floor and the frame rate goes with them.
const MAX_HOLES := 96

var _tracer_material: StandardMaterial3D
var _impact_world: StandardMaterial3D
var _impact_flesh: StandardMaterial3D
var _hole_material: StandardMaterial3D
var _hole_mesh: QuadMesh
var _holes: Array[MeshInstance3D] = []

func _ready() -> void:
	_tracer_material = _unshaded(Color(1.0, 0.92, 0.62), 2.2)
	_impact_world = _unshaded(Color(1.0, 0.85, 0.55), 2.6)
	_impact_flesh = _unshaded(Color(1.0, 0.32, 0.30), 2.6)
	_build_hole_resources()

func _unshaded(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	return mat

## A thin streak from muzzle to impact. Very short-lived: long tracers read as
## lasers rather than bullets.
func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	# Below this the streak is shorter than it is wide and reads as a speck.
	if length < 0.12:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.028, 0.028, length)
	mesh.mesh = box
	mesh.material_override = _tracer_material.duplicate()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	# look_at fails when the direction is parallel to the up vector; a shot
	# fired straight down is rare but not impossible.
	var direction := (to - from).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mesh.look_at(to, up)
	_fade_and_free(mesh, mesh.material_override, TRACER_SECONDS)

## Bullet holes are oriented quads, not [Decal] nodes. Decals need Forward+ or
## Mobile, and this project renders through the Compatibility backend so the
## browser build works and the editor stops crashing on machines without a
## Vulkan driver -- see docs/architecture.md. A camera-independent quad nudged
## off the surface is the portable equivalent.
func _build_hole_resources() -> void:
	_hole_mesh = QuadMesh.new()
	_hole_mesh.size = Vector2(0.20, 0.20)

	_hole_material = StandardMaterial3D.new()
	_hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hole_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hole_material.albedo_texture = _make_hole_texture(32)
	_hole_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hole_material.disable_receive_shadows = true
	# Drawn after opaque geometry so the quad wins the depth tie with the wall
	# it is sitting a centimetre in front of.
	_hole_material.render_priority = 1

## A dark core inside a light chipped rim, fading out at the edge.
##
## The obvious version -- a dark blob -- is invisible on dark geometry, and this
## arena has both near-white floors and near-black walls. A mark that carries
## its own contrast reads on either, which is the whole job: the player has to
## see where their shots went without first knowing what colour the wall was.
func _make_hole_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var centre := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(float(x) - centre, float(y) - centre).length() / centre
			# A wide dark core with a thin bright ring around it. The core is
			# what shows on pale floors, the ring is what shows on dark walls.
			var core := 1.0 - smoothstep(0.34, 0.54, distance)
			var rim := smoothstep(0.44, 0.62, distance) * (1.0 - smoothstep(0.68, 0.96, distance))
			var alpha := clampf(maxf(core, rim * 0.92), 0.0, 1.0)
			var value := lerpf(0.86, 0.02, core)
			image.set_pixel(x, y, Color(value, value, value, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## A lasting mark on world geometry. Not spawned on characters -- a hole
## hanging in the air after a target revives looks like a bug.
func bullet_hole(position: Vector3, normal: Vector3) -> void:
	if _holes.size() >= MAX_HOLES:
		var oldest: MeshInstance3D = _holes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var hole := MeshInstance3D.new()
	hole.mesh = _hole_mesh
	hole.material_override = _hole_material.duplicate()
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hole)

	# Lifted off the surface, or it z-fights with the wall.
	hole.global_position = position + normal * 0.012
	# A QuadMesh faces +Z, and look_at aims -Z, so aim it *away* from the
	# surface to leave the face pointing back out along the normal.
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	hole.look_at(hole.global_position - normal, reference)
	hole.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	hole.scale = Vector3.ONE * randf_range(0.8, 1.15)
	_holes.append(hole)

	var tween := create_tween()
	tween.tween_interval(HOLE_SECONDS * 0.75)
	tween.tween_property(hole.material_override, "albedo_color:a", 0.0, HOLE_SECONDS * 0.25)
	tween.tween_callback(func() -> void:
		_holes.erase(hole)
		hole.queue_free())

func impact(position: Vector3, normal: Vector3, on_character: bool) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.10
	sphere.height = 0.20
	sphere.radial_segments = 6
	sphere.rings = 3
	mesh.mesh = sphere
	mesh.material_override = (_impact_flesh if on_character else _impact_world).duplicate()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	# Nudge off the surface so it does not z-fight with the wall it marks.
	mesh.global_position = position + normal * 0.02
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3(0.2, 0.2, 0.2), IMPACT_SECONDS)
	tween.tween_property(mesh.material_override, "albedo_color:a", 0.0, IMPACT_SECONDS)
	tween.chain().tween_callback(mesh.queue_free)

func damage_number(position: Vector3, amount: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.font_size = 44
	label.pixel_size = 0.0035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1.0, 0.78, 0.25) if headshot else Color(1, 1, 1)
	label.no_depth_test = true
	add_child(label)
	# Small random sideways drift so a burst does not stack numbers into an
	# unreadable pile on one pixel.
	var drift := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	label.global_position = position + Vector3.UP * 0.15
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position",
			position + Vector3.UP * 0.95 + drift, NUMBER_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, NUMBER_SECONDS) \
			.set_delay(NUMBER_SECONDS * 0.45)
	tween.chain().tween_callback(label.queue_free)

func _fade_and_free(node: Node3D, material: StandardMaterial3D, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(node.queue_free)
