class_name ViewModel
extends Node3D
## Placeholder first-person weapon, built from boxes.
##
## Explicitly a stand-in: there is no art yet, and a blockout gun that kicks and
## sways answers "does firing feel connected to anything" far better than an
## empty screen does. Milestone 6's art pass replaces the mesh; the motion here
## is the part worth keeping.
##
## Sits under [CameraRig] so it inherits view bob for free, and draws with depth
## testing off so it does not clip through walls -- the usual fix is a second
## camera on its own render layer, which is not worth the complexity until
## there is a real model to show.

## Rest position, in camera space. Godot cameras look down -Z.
##
## Pushed far enough out that no part of the model sits closer than about
## 0.36 m. At the game's 90 degree FOV anything nearer than that fills a
## quarter of the screen -- real shooters dodge this by rendering the weapon
## through a second camera with its own narrower FOV, which is not worth the
## complexity for a placeholder. Keeping the model compact and distant gets
## most of the way there.
const HIP := Vector3(0.20, -0.195, -0.52)
## Centred when aiming, with the vertical offset cancelling the sight's own
## height so the sight sits on the crosshair the shots actually follow.
## Pushed *further* out than the hip pose, not closer. Bringing a chunky
## placeholder toward the eye centres the sight but buries the crosshair behind
## the receiver; holding it at arm's length keeps the target visible, which
## matters more than the realism of the gesture.
const ADS := Vector3(0.0, -0.078, -0.60)
## Dropped and angled away while sprinting: a clear "you cannot shoot right
## now" signal that costs no HUD space.
const SPRINT := Vector3(0.24, -0.30, -0.48)

const SETTLE_SPEED := 14.0
const KICK_STIFFNESS := 220.0
const KICK_DAMPING := 21.0
const KICK_TIMESTEP := 1.0 / 240.0

var _controller: PlayerController
var _kick: float = 0.0
var _kick_velocity: float = 0.0
var _sway: Vector2 = Vector2.ZERO

func _ready() -> void:
	_controller = _find_controller()
	if _controller == null:
		set_process(false)
		return
	position = HIP
	_build_mesh()
	if _controller.weapons != null:
		_controller.weapons.fired.connect(_on_fired)

func _find_controller() -> PlayerController:
	var node := get_parent()
	while node != null:
		if node is PlayerController:
			return node
		node = node.get_parent()
	return null

func _on_fired(_weapon: WeaponResource) -> void:
	# One impulse per shot, so a burst stacks the way a real one does.
	_kick_velocity += 5.0

func _process(delta: float) -> void:
	var target := HIP
	var sprinting := _controller.get_horizontal_speed() > _controller.config.walk_speed + 0.5 \
			and _controller.is_on_floor()
	if _controller.is_aiming:
		target = ADS
	elif sprinting:
		target = SPRINT

	_update_kick(delta)
	_update_sway(delta, target == ADS)

	var weight := 1.0 - exp(-delta * SETTLE_SPEED)
	# The kick pushes the weapon back toward the camera, not down the barrel.
	var kicked := target + Vector3(_sway.x, _sway.y, _kick * 0.06)
	position = position.lerp(kicked, weight)
	rotation.x = lerpf(rotation.x, -_kick * 0.05 - _sway.y * 2.0, weight)
	rotation.y = lerpf(rotation.y, -_sway.x * 2.5, weight)

## Fixed substep, same reason as the landing dip: an explicit spring stepped on
## the render frame recoils visibly harder at high frame rates.
func _update_kick(delta: float) -> void:
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, KICK_TIMESTEP)
		_kick_velocity += (-KICK_STIFFNESS * _kick - KICK_DAMPING * _kick_velocity) * step
		_kick += _kick_velocity * step
		remaining -= step

## Lag the weapon behind the view a little. Reduced while aiming, where the
## player is trying to hold a precise line and a swinging gun reads as drift.
func _update_sway(delta: float, aiming: bool) -> void:
	var amount := 0.006 if aiming else 0.022
	var target := Vector2(
		clampf(-_controller.cmd.move_axis.x, -1.0, 1.0) * amount,
		clampf(_controller.velocity.y / 12.0, -1.0, 1.0) * amount * 0.7)
	_sway = _sway.lerp(target, 1.0 - exp(-delta * 7.0))

func _build_mesh() -> void:
	var metal := _material(Color(0.16, 0.17, 0.20), 0.55)
	var accent := _material(Color(0.30, 0.32, 0.36), 0.45)
	# name, size, position
	# Deliberately stubby. A realistically proportioned rifle recedes so far up
	# the view axis at 90 degrees FOV that it reads as a stick; compressing the
	# length keeps the silhouette legible.
	var parts := [
		["Stock", Vector3(0.050, 0.068, 0.11), Vector3(0.0, -0.012, 0.100), accent],
		["Receiver", Vector3(0.066, 0.086, 0.22), Vector3(0.0, 0.0, -0.060), metal],
		["Magazine", Vector3(0.042, 0.115, 0.060), Vector3(0.0, -0.085, -0.045), accent],
		["Grip", Vector3(0.042, 0.092, 0.054), Vector3(0.0, -0.068, 0.046), metal],
		["Handguard", Vector3(0.046, 0.050, 0.14), Vector3(0.0, 0.004, -0.240), metal],
		["Barrel", Vector3(0.026, 0.026, 0.16), Vector3(0.0, 0.010, -0.350), accent],
		["Sight", Vector3(0.014, 0.030, 0.016), Vector3(0.0, 0.078, -0.140), accent],
	]
	for part in parts:
		var mesh := MeshInstance3D.new()
		mesh.name = part[0]
		var box := BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.position = part[2]
		mesh.material_override = part[3]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.3
	# Drawn over the world so the barrel does not vanish into walls.
	mat.no_depth_test = true
	mat.render_priority = 1
	return mat
