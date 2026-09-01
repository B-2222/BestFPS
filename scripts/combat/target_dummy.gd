class_name TargetDummy
extends Node3D
## A shootable practice target, built in code like the rest of the blockout.
##
## Deliberately the same shape and hitbox layout a bot will have in Milestone 3
## -- head, torso, legs, each on the hitbox layer with its own multiplier -- so
## the time-to-kill numbers tuned against these dummies stay true when the
## targets start shooting back.
##
## Shows its own health and range in world space. Reading "3 shots, 66 damage,
## 30 m" off the target itself is what turns "the rifle feels weak" into a
## number we can act on.

## Metres. Set non-zero to make the target strafe, for tracking practice and,
## in Milestone 5, for testing lag compensation against a moving hitbox.
@export var patrol_range: float = 0.0
@export var patrol_speed: float = 3.0
@export var patrol_axis: Vector3 = Vector3.RIGHT

var health: Health
var recorder: HitboxRecorder

var _parts: Array[MeshInstance3D] = []
## Base albedo per part, so the hit flash can be applied as an offset from a
## known colour rather than blended from whatever the last frame left behind.
var _base_colors: Array[Color] = []
var _label: Label3D
var _origin: Vector3
var _phase: float = 0.0
var _flash: float = 0.0
var _tick: int = 0

const PARTS := [
	# id, size, centre height, damage multiplier
	[&"legs", Vector3(0.50, 0.90, 0.34), 0.45, 0.80],
	[&"body", Vector3(0.62, 0.66, 0.34), 1.23, 1.00],
	[&"head", Vector3(0.28, 0.28, 0.28), 1.70, 1.00],
]

func _ready() -> void:
	_origin = position

	health = Health.new()
	health.name = "Health"
	health.max_health = 100.0
	health.auto_revive_after = 3.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)

	for part in PARTS:
		_build_part(part[0], part[1], part[2], part[3])

	_label = Label3D.new()
	_label.position = Vector3(0.0, 2.25, 0.0)
	_label.font_size = 40
	_label.pixel_size = 0.0038
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.shaded = false
	_label.outline_size = 9
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(_label)

	# Added last so it finds every hitbox already in the tree.
	recorder = HitboxRecorder.new()
	recorder.name = "HitboxRecorder"
	add_child(recorder)

	_refresh_label()

func _build_part(id: StringName, size: Vector3, height: float, multiplier: float) -> void:
	var hitbox := Hitbox.new()
	hitbox.name = String(id).capitalize() + "Hitbox"
	hitbox.hitbox_id = id
	hitbox.damage_multiplier = multiplier
	hitbox.position = Vector3(0.0, height, 0.0)
	add_child(hitbox)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	hitbox.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var base := Color(0.92, 0.55, 0.20) if id == &"head" else Color(0.72, 0.74, 0.80)
	var material := StandardMaterial3D.new()
	material.albedo_color = base
	material.roughness = 0.8
	mesh.material_override = material
	hitbox.add_child(mesh)
	_parts.append(mesh)
	_base_colors.append(base)

func _physics_process(delta: float) -> void:
	_tick += 1
	if patrol_range > 0.0:
		_phase += delta * patrol_speed / maxf(patrol_range, 0.001)
		position = _origin + patrol_axis.normalized() * sin(_phase) * patrol_range
	# Record after moving, so the history holds where the hitboxes actually
	# were at the end of this tick.
	if recorder != null:
		recorder.record(_tick)

func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_apply_flash()

## Always derived from the stored base colour. Blending from the *current*
## colour instead meant every hit dragged the part permanently toward the flash
## and then toward white as it decayed -- which quietly erased the orange head
## that tells the player where the headshot box is.
func _apply_flash() -> void:
	var hit := Color(1.0, 0.35, 0.30)
	for i in _parts.size():
		var material := _parts[i].material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = _base_colors[i].lerp(hit, _flash)

func _on_damaged(_info: DamageInfo, _remaining: float) -> void:
	_flash = 1.0
	_refresh_label()

func _on_died(_info: DamageInfo) -> void:
	_label.text = "DOWN"
	_label.modulate = Color(1.0, 0.35, 0.30)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", deg_to_rad(-80.0), 0.35) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

func _on_revived() -> void:
	rotation.x = 0.0
	_flash = 0.0
	_apply_flash()
	_refresh_label()

func _refresh_label() -> void:
	_label.modulate = Color(1, 1, 1)
	_label.text = "%d hp" % roundi(health.current)
