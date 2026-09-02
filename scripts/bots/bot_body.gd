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

## view_shape -> [size, forward offset]. Silhouette only; nobody sees the
## detail on these at fighting range.
const SHAPES := {
	&"rifle": [Vector3(0.07, 0.10, 0.62), 0.28],
	&"shotgun": [Vector3(0.09, 0.12, 0.72), 0.32],
	&"sniper": [Vector3(0.06, 0.10, 0.92), 0.42],
	&"pistol": [Vector3(0.06, 0.13, 0.24), 0.14],
}

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
	# Just off centre at chest height, pointing where the head points -- which
	# is what makes a bot's aim readable from across the arena. Near the centre
	# line rather than out at the shoulder so the figure's two arms converge on
	# it instead of one arm appearing to hold nothing.
	position = Vector3(0.11, -0.30, 0.0)

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
