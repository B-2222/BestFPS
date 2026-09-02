class_name ViewModel
extends Node3D
## Placeholder first-person weapons, built from boxes, one shape per weapon.
##
## Explicitly stand-ins: there is no art yet. Good CC0 gun models do exist
## (Quaternius and Kenney both ship glTF packs), but they are blocked by this
## environment's network policy and, more to the point, a realistic model would
## sit oddly against a grey-box arena. The shapes here exist to make the four
## weapons *readable at a glance* -- you should know what you are holding from
## the silhouette alone -- and the motion is the part worth keeping when real
## models arrive.
##
## Sits under [CameraRig] so it inherits view bob, and draws with depth testing
## off so it does not clip through walls. The usual fix is a second camera on
## its own render layer, which is not worth the complexity for a placeholder.

const SETTLE_SPEED := 14.0
const KICK_STIFFNESS := 220.0
const KICK_DAMPING := 21.0
const KICK_TIMESTEP := 1.0 / 240.0

## Per-weapon silhouette and poses. "hip"/"ads"/"sprint" are camera-space
## positions; everything is pushed far enough out that no part sits closer than
## about 0.35 m, because at 90 degrees FOV anything nearer fills the screen.
const SHAPES := {
	&"rifle": {
		"hip": Vector3(0.20, -0.195, -0.52),
		"ads": Vector3(0.0, -0.078, -0.60),
		"sprint": Vector3(0.24, -0.30, -0.48),
		"muzzle": Vector3(0.0, 0.010, -0.430),
		"parts": [
			["Stock", Vector3(0.050, 0.068, 0.11), Vector3(0.0, -0.012, 0.100), "accent"],
			["Receiver", Vector3(0.066, 0.086, 0.22), Vector3(0.0, 0.0, -0.060), "metal"],
			["Magazine", Vector3(0.042, 0.115, 0.060), Vector3(0.0, -0.085, -0.045), "accent"],
			["Grip", Vector3(0.042, 0.092, 0.054), Vector3(0.0, -0.068, 0.046), "metal"],
			["Handguard", Vector3(0.046, 0.050, 0.14), Vector3(0.0, 0.004, -0.240), "metal"],
			["Barrel", Vector3(0.026, 0.026, 0.16), Vector3(0.0, 0.010, -0.350), "accent"],
			["Sight", Vector3(0.014, 0.030, 0.016), Vector3(0.0, 0.078, -0.140), "accent"],
		],
	},
	&"shotgun": {
		"hip": Vector3(0.21, -0.200, -0.50),
		"ads": Vector3(0.0, -0.076, -0.58),
		"sprint": Vector3(0.25, -0.30, -0.46),
		"muzzle": Vector3(0.0, 0.014, -0.410),
		"parts": [
			["Stock", Vector3(0.055, 0.078, 0.13), Vector3(0.0, -0.020, 0.110), "accent"],
			["Receiver", Vector3(0.076, 0.096, 0.20), Vector3(0.0, 0.0, -0.050), "metal"],
			["Grip", Vector3(0.046, 0.090, 0.056), Vector3(0.0, -0.068, 0.050), "metal"],
			["Handguard", Vector3(0.062, 0.058, 0.13), Vector3(0.0, -0.032, -0.215), "accent"],
			["Barrel", Vector3(0.040, 0.040, 0.26), Vector3(0.0, 0.016, -0.280), "metal"],
			["Tube", Vector3(0.030, 0.030, 0.24), Vector3(0.0, -0.026, -0.270), "accent"],
			["Sight", Vector3(0.012, 0.022, 0.014), Vector3(0.0, 0.052, -0.160), "accent"],
		],
	},
	&"sniper": {
		"hip": Vector3(0.22, -0.205, -0.56),
		"ads": Vector3(0.0, -0.090, -0.66),
		"sprint": Vector3(0.26, -0.31, -0.52),
		"muzzle": Vector3(0.0, 0.010, -0.560),
		"parts": [
			["Stock", Vector3(0.050, 0.082, 0.17), Vector3(0.0, -0.018, 0.140), "accent"],
			["Receiver", Vector3(0.062, 0.082, 0.24), Vector3(0.0, 0.0, -0.030), "metal"],
			["Magazine", Vector3(0.038, 0.078, 0.050), Vector3(0.0, -0.072, -0.030), "accent"],
			["Grip", Vector3(0.042, 0.095, 0.052), Vector3(0.0, -0.070, 0.075), "metal"],
			["Barrel", Vector3(0.026, 0.026, 0.40), Vector3(0.0, 0.010, -0.360), "metal"],
			["ScopeMountRear", Vector3(0.018, 0.042, 0.020), Vector3(0.0, 0.058, -0.030), "metal"],
			["ScopeMountFront", Vector3(0.018, 0.042, 0.020), Vector3(0.0, 0.058, -0.165), "metal"],
			["Scope", Vector3(0.044, 0.044, 0.21), Vector3(0.0, 0.090, -0.100), "accent"],
		],
	},
	&"pistol": {
		"hip": Vector3(0.17, -0.175, -0.44),
		"ads": Vector3(0.0, -0.052, -0.50),
		"sprint": Vector3(0.21, -0.27, -0.42),
		"muzzle": Vector3(0.0, 0.020, -0.205),
		"parts": [
			["Slide", Vector3(0.048, 0.058, 0.20), Vector3(0.0, 0.020, -0.060), "metal"],
			["Frame", Vector3(0.044, 0.040, 0.16), Vector3(0.0, -0.022, -0.040), "accent"],
			["Grip", Vector3(0.046, 0.115, 0.062), Vector3(0.0, -0.098, 0.046), "metal"],
			["Magazine", Vector3(0.034, 0.090, 0.046), Vector3(0.0, -0.108, 0.046), "accent"],
			["Barrel", Vector3(0.020, 0.020, 0.06), Vector3(0.0, 0.020, -0.180), "accent"],
			["Sight", Vector3(0.010, 0.016, 0.012), Vector3(0.0, 0.052, -0.130), "accent"],
		],
	},
}

var _controller: PlayerController
var _weapons: WeaponController
var _shape_id: StringName = &""
var _shape: Dictionary = {}

var _muzzle: Marker3D
var _flash: MeshInstance3D
var _flash_life: float = 0.0
var _magazine: MeshInstance3D
var _magazine_home: Vector3 = Vector3.ZERO
var _handguard: MeshInstance3D
var _handguard_home: Vector3 = Vector3.ZERO

var _kick: float = 0.0
var _kick_velocity: float = 0.0
var _sway: Vector2 = Vector2.ZERO

func _ready() -> void:
	_controller = _find_controller()
	if _controller == null:
		set_process(false)
		return
	# Deliberately not resolving the weapon controller here. Godot readies
	# children before parents, and this node is three levels below the player,
	# so PlayerController._ready() has not run yet and its @onready reference
	# to the WeaponController is still null. Resolved on the first frame
	# instead -- getting this wrong silently left every weapon drawing the
	# rifle, because the fallback shape was the only one ever built.
	_rebuild(&"rifle", null)

## Connect on the first frame, once the player has actually readied.
func _ensure_weapons() -> void:
	if _weapons != null or _controller.weapons == null:
		return
	_weapons = _controller.weapons
	_weapons.fired.connect(_on_fired)
	_weapons.weapon_changed.connect(_on_weapon_changed)
	var runtime := _weapons.current()
	if runtime != null:
		_rebuild(runtime.resource.view_shape, runtime.resource)

func _find_controller() -> PlayerController:
	var node := get_parent()
	while node != null:
		if node is PlayerController:
			return node
		node = node.get_parent()
	return null

## World position of the barrel tip, for whoever is drawing the shot.
func get_muzzle_position() -> Vector3:
	if _muzzle == null:
		return global_position
	return _muzzle.global_position

func _on_weapon_changed(weapon: WeaponResource) -> void:
	_rebuild(weapon.view_shape, weapon)

func _on_fired(_weapon: WeaponResource) -> void:
	# One impulse per shot, so a burst stacks the way a real one does.
	_kick_velocity += 5.0
	_flash_life = 1.0
	if _flash != null:
		_flash.visible = true
		# Rolled at random so a held trigger does not strobe one fixed shape.
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.85, 1.25)

# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_ensure_weapons()
	var runtime: WeaponRuntime = _weapons.current() if _weapons != null else null

	var target: Vector3 = _shape.get("hip", Vector3.ZERO)
	var sprinting := _controller.get_horizontal_speed() > _controller.config.walk_speed + 0.5 \
			and _controller.is_on_floor()
	if _controller.is_aiming:
		target = _shape.get("ads", target)
	elif sprinting:
		target = _shape.get("sprint", target)

	_update_kick(delta)
	_update_sway(delta, _controller.is_aiming)
	_update_flash(delta)

	var extra_rotation := Vector3.ZERO
	if runtime != null:
		target += _pose_offset(runtime, extra_rotation)
		extra_rotation = _pose_rotation(runtime)
	_animate_parts(runtime)

	# A scoped weapon is hidden once the optic takes over the screen. You are
	# looking through the sight, not past the gun, and leaving the model in
	# view is exactly what made the sniper feel like staring at a block.
	visible = not (_controller.aim_has_scope and _controller.aim_blend > 0.55)

	var weight := 1.0 - exp(-delta * SETTLE_SPEED)
	# The kick pushes the weapon back toward the camera, not down the barrel.
	var kicked := target + Vector3(_sway.x, _sway.y, _kick * 0.06)
	position = position.lerp(kicked, weight)
	rotation.x = lerpf(rotation.x, -_kick * 0.05 - _sway.y * 2.0 + extra_rotation.x, weight)
	rotation.y = lerpf(rotation.y, -_sway.x * 2.5 + extra_rotation.y, weight)
	rotation.z = lerpf(rotation.z, extra_rotation.z, weight)

## Positional offset for whatever the weapon is busy doing: dropped out of view
## while swapping, tipped down and aside while reloading.
func _pose_offset(runtime: WeaponRuntime, _unused: Vector3) -> Vector3:
	match runtime.phase:
		WeaponRuntime.Phase.EQUIPPING:
			# Lowest at the start of the swap, back up as it completes.
			return Vector3(0.0, -0.34, 0.05) * (1.0 - runtime.phase_progress())
		WeaponRuntime.Phase.RELOADING:
			# sin() so it dips away and returns rather than snapping back.
			var arc := sin(runtime.phase_progress() * PI)
			return Vector3(-0.045, -0.13, 0.03) * arc
	return Vector3.ZERO

func _pose_rotation(runtime: WeaponRuntime) -> Vector3:
	match runtime.phase:
		WeaponRuntime.Phase.EQUIPPING:
			return Vector3(-0.85 * (1.0 - runtime.phase_progress()), 0.0, 0.0)
		WeaponRuntime.Phase.RELOADING:
			var arc := sin(runtime.phase_progress() * PI)
			return Vector3(-0.55 * arc, 0.22 * arc, 0.30 * arc)
	return Vector3.ZERO

## Moving parts: the magazine drops and is replaced, or the pump cycles.
## Driven off phase_progress rather than a timer, so it stays in step with the
## reload however long the weapon's reload actually is.
func _animate_parts(runtime: WeaponRuntime) -> void:
	var reloading := runtime != null and runtime.phase == WeaponRuntime.Phase.RELOADING
	var progress := runtime.phase_progress() if reloading else 1.0
	var style: StringName = runtime.resource.reload_style if runtime != null else &"magazine"

	if _magazine != null:
		if reloading and style == &"magazine":
			# Out between 15% and 45%, gone until 60%, seated by 80%.
			var drop := smoothstep(0.15, 0.45, progress) - smoothstep(0.60, 0.80, progress)
			_magazine.position = _magazine_home - Vector3(0.0, 0.22 * drop, 0.0)
			_magazine.visible = drop < 0.98
		else:
			_magazine.position = _magazine_home
			_magazine.visible = true

	if _handguard != null:
		if reloading and style == &"pump":
			# Three racks across the reload, each a full back-and-forward.
			var cycle := maxf(sin(progress * PI * 6.0), 0.0)
			_handguard.position = _handguard_home + Vector3(0.0, 0.0, 0.075 * cycle)
		else:
			_handguard.position = _handguard_home

## The flash is one reused mesh rather than a spawned effect: at 600 rpm this
## fires ten times a second, and allocating a node and a material per shot to
## show something for 45 ms is pure churn.
func _update_flash(delta: float) -> void:
	if _flash == null or _flash_life <= 0.0:
		return
	_flash_life = maxf(_flash_life - delta * 22.0, 0.0)
	_flash.scale = Vector3.ONE * (0.5 + _flash_life * 0.9)
	if _flash_life <= 0.0:
		_flash.visible = false

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

# ---------------------------------------------------------------------------

func _rebuild(shape_id: StringName, weapon: WeaponResource) -> void:
	if shape_id == _shape_id:
		return
	_shape_id = shape_id
	_shape = SHAPES.get(shape_id, SHAPES[&"rifle"])
	_magazine = null
	_handguard = null
	# Removed as well as freed: queue_free() only takes effect at the end of the
	# frame, so without the remove_child the old weapon renders on top of the
	# new one for a frame on every swap.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	if weapon != null and weapon.view_model_scene != null:
		_build_model(weapon)
		return
	_build_silhouette()

## Instance a real model in place of the boxes.
##
## Everything downstream is unaffected: pose, sway, kick and the reload
## animation all act on this node, not on the geometry under it, and the shot
## itself is traced from the player's eye regardless. Swapping art cannot change
## where bullets go, which is the point of having kept those apart.
func _build_model(weapon: WeaponResource) -> void:
	var model := weapon.view_model_scene.instantiate() as Node3D
	if model == null:
		push_warning("ViewModel: %s has a view_model_scene whose root is not a Node3D."
				% weapon.display_name)
		_build_silhouette()
		return
	model.name = "Model"
	model.scale = Vector3.ONE * weapon.model_scale
	model.rotation_degrees = weapon.model_rotation_degrees
	add_child(model)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		# First-person geometry must not self-shadow into the scene; it lives a
		# few centimetres from the camera and would throw a shadow across the
		# whole view.
		(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_magazine = model.find_child("Magazine", true, false) as MeshInstance3D
	if _magazine != null:
		_magazine_home = _magazine.position
	_handguard = model.find_child("Handguard", true, false) as MeshInstance3D
	if _handguard != null:
		_handguard_home = _handguard.position
	_finish(weapon.model_muzzle)

func _build_silhouette() -> void:
	var materials := {
		"metal": _material(Color(0.16, 0.17, 0.20), 0.55),
		"accent": _material(Color(0.30, 0.32, 0.36), 0.45),
	}
	for part in _shape["parts"]:
		var mesh := MeshInstance3D.new()
		mesh.name = part[0]
		var box := BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.position = part[2]
		mesh.material_override = materials[part[3]]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		if part[0] == "Magazine":
			_magazine = mesh
			_magazine_home = mesh.position
		elif part[0] == "Handguard":
			_handguard = mesh
			_handguard_home = mesh.position

	_finish(_shape["muzzle"])

func _finish(muzzle: Vector3) -> void:
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = muzzle
	add_child(_muzzle)
	_build_flash()

func _build_flash() -> void:
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.86, 0.52, 0.9)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.80, 0.42)
	flash_material.emission_energy_multiplier = 4.0
	flash_material.no_depth_test = true
	flash_material.render_priority = 2

	_flash = MeshInstance3D.new()
	_flash.name = "MuzzleFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.045
	flash_mesh.height = 0.09
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	_flash.mesh = flash_mesh
	_flash.material_override = flash_material
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_muzzle.add_child(_flash)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.3
	# Drawn over the world so the barrel does not vanish into walls.
	mat.no_depth_test = true
	mat.render_priority = 1
	return mat
