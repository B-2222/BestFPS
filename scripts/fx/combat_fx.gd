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

const TRACER_SECONDS := 0.07
const IMPACT_SECONDS := 0.22
const NUMBER_SECONDS := 0.75

var _tracer_material: StandardMaterial3D
var _impact_world: StandardMaterial3D
var _impact_flesh: StandardMaterial3D

func _ready() -> void:
	_tracer_material = _unshaded(Color(1.0, 0.92, 0.62), 2.2)
	_impact_world = _unshaded(Color(1.0, 0.85, 0.55), 2.6)
	_impact_flesh = _unshaded(Color(1.0, 0.32, 0.30), 2.6)

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
	if length < 0.2:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, length)
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

func impact(position: Vector3, normal: Vector3, on_character: bool) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
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
