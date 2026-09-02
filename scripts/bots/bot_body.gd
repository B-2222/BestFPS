class_name BotBody
extends Node3D
## The weapon a bot is visibly holding.
##
## Purely for readability, and worth the thirty lines: bots now draw from a
## mixed weapon rotation, and "that one has a shotgun, do not let it close" is
## a decision you can only make if you can see what it is carrying. Without
## this, every bot looks identical and the only way to learn what one is
## holding is to be shot by it.
##
## Deliberately not the first-person [ViewModel]: that geometry is built to
## look right at 30 cm from a camera, and reusing it here would put a
## comically large gun in a bot's hands.

## view_shape -> [size, forward offset, rear grip z, front grip z]. Silhouette
## only; nobody sees the detail on these at fighting range.
##
## The two grip offsets are measured from this node and are what the figure's
## hands are solved onto, so a longer weapon is held further apart -- which is
## the difference between a character holding a rifle and one holding a plank.
const SHAPES := {
	&"rifle": [Vector3(0.07, 0.10, 0.62), 0.28, -0.10, -0.26],
	&"shotgun": [Vector3(0.09, 0.12, 0.72), 0.32, -0.10, -0.30],
	&"sniper": [Vector3(0.06, 0.10, 0.92), 0.42, -0.12, -0.34],
	&"pistol": [Vector3(0.06, 0.13, 0.24), 0.14, -0.06, -0.13],
}

## Where the hands go, in this node's space: rear (trigger) then front (support).
var grips: Array[Vector3] = [Vector3(0.0, -0.04, -0.10), Vector3(0.0, -0.04, -0.26)]

@export var weapons_path: NodePath = ^"../../WeaponController"

var _mesh: MeshInstance3D
var _box: BoxMesh
var _weapons: WeaponController
var _model: Node3D

func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = SHAPES[&"rifle"][0]
	_mesh = MeshInstance3D.new()
	_mesh.name = "Weapon"
	_mesh.mesh = _box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.14, 0.17)
	material.roughness = 0.45
	material.metallic = 0.5
	_mesh.material_override = material
	add_child(_mesh)
	add_to_group(&"character_weapon")
	# Held out *in front of* the chest, not on the centre of it. Placed at the
	# torso's own depth the weapon was buried inside the body with only its
	# barrel poking out, which is what it looked like: a gun growing out of
	# somebody's sternum.
	#
	# Still parented to the head, so it pitches with aim. That is the cue that
	# lets you read where a bot is looking from across the arena, and it is
	# worth more than having the hands and the weapon share a parent.
	position = Vector3(0.02, -0.28, -0.22)

## Resolved on the first frame, not in _ready(): this node is a descendant of
## the controller, so it becomes ready first and the controller's @onready
## references are still null here. Same trap as everywhere else in this project.
func _process(_delta: float) -> void:
	if _weapons != null:
		return
	_weapons = get_node_or_null(weapons_path) as WeaponController
	if _weapons == null:
		set_process(false)
		return
	_weapons.weapon_changed.connect(_on_weapon_changed)
	var rt := _weapons.current()
	if rt != null:
		_on_weapon_changed(rt.resource)
	set_process(false)

## The two points a pair of hands should be at, in world space.
##
## Duck-typed rather than exposed through a class reference: [CharacterFigure]
## lives in scripts/combat and has no business knowing what a bot is, so it
## looks for any descendant that answers this and solves its arms onto whatever
## comes back.
func grip_points() -> Array:
	return [to_global(grips[0]), to_global(grips[1])]

func _on_weapon_changed(weapon: WeaponResource) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	if weapon.world_model_scene != null:
		# A real model replaces the silhouette outright. Same drop-in point as
		# the first-person view: see WeaponResource's Models group.
		var model := weapon.world_model_scene.instantiate() as Node3D
		if model != null:
			model.scale = Vector3.ONE * weapon.model_scale
			model.rotation_degrees = weapon.model_rotation_degrees
			add_child(model)
			_model = model
			_mesh.visible = false
			return
	_mesh.visible = true
	var shape: Array = SHAPES.get(weapon.view_shape, SHAPES[&"rifle"])
	_box.size = shape[0]
	_mesh.position = Vector3(0.0, 0.0, -float(shape[1]))
	grips = [Vector3(0.0, -0.04, float(shape[2])),
			Vector3(0.0, -0.04, float(shape[3]))]
