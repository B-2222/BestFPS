@tool
class_name ArenaBuilder
extends Node3D
## Builds the Milestone 1 movement test blockout in code.
##
## Deliberately procedural rather than hand-placed. This level exists to
## *measure* the controller -- "can I clear a 4 m gap", "is a 0.35 m ledge a
## step or a wall" -- and numbers in a table are easier to trust and to change
## than nodes dragged in a viewport. Milestone 4 replaces this with a
## handcrafted arena; this one is an instrument, not a map.
##
## Every obstacle is labelled in-world with its dimension, so feedback can be
## "the 4 m gap needs a run-up" instead of "some jumps feel short".

## Where the player spawns, and reference points the smoke test drives to.
const SPAWN := Vector3(0.0, 1.0, 0.0)
const MARK_STAIRS_SMALL := Vector3(8.0, 1.0, -6.0)
const MARK_SLIDE_TOP := Vector3(-25.0, 5.0, -8.0)

const ARENA_SIZE := 80.0
const WALL_HEIGHT := 6.0

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_step: StandardMaterial3D
var _mat_jump: StandardMaterial3D
var _mat_ramp: StandardMaterial3D
var _mat_blocked: StandardMaterial3D
var _mat_slide: StandardMaterial3D

## Build the blockout inside the editor as well as at runtime.
##
## Off by default. Opening the scene otherwise generates ~90 nodes, a texture
## and 40 Label3Ds every single time, which is pure cost on a machine that is
## already struggling -- and none of it is saved to the scene anyway, since the
## nodes have no owner. Turn it on only if you want to look at the level in the
## viewport.
@export var build_in_editor: bool = false

## The blockout root is a NavigationRegion3D so the bots in Milestone 3 can be
## given a navigation mesh baked from the same geometry the player collides
## with -- one source of truth for "where can something stand".
var _geometry_root: NavigationRegion3D

func _ready() -> void:
	if Engine.is_editor_hint() and not build_in_editor:
		return
	build()

func build() -> void:
	if _geometry_root != null and is_instance_valid(_geometry_root):
		_geometry_root.queue_free()
	_geometry_root = NavigationRegion3D.new()
	_geometry_root.name = "Blockout"
	add_child(_geometry_root)

	_build_materials()
	_build_environment()
	_build_shell()
	_build_distance_lane()
	_build_step_ledges()
	_build_staircases()
	_build_jump_heights()
	_build_gap_walkway()
	_build_ramps()
	_build_slide_slope()
	_build_crouch_tunnel()
	_build_pillars()
	_build_shooting_range()
	_bake_navigation()

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

## Bake the navigation mesh from the static colliders we just built.
##
## Baked at runtime rather than saved, because the geometry is generated at
## runtime -- there is nothing to bake in the editor. Parsing static colliders
## on the world layer rather than mesh instances keeps the labels, the target
## dummies and their hitbox Areas out of it: a bot should navigate the same
## surfaces the player collides with, not the decoration.
##
## The agent parameters deliberately mirror the player's own hull and limits,
## so anywhere a bot is told it can walk, a player could walk too.
func _bake_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.35   # PlayerConfig.max_step_height
	mesh.agent_max_slope = 46.0   # PlayerConfig.floor_max_angle_deg
	# Both are rounded to voxel units at bake time, so they are chosen to land
	# exactly on a multiple: 0.35 climb is 7 cells of 0.05, and 0.4 radius is
	# 2 cells of 0.2. Left at coarser values, max_climb floors to 0.30 and the
	# 0.35 m staircases silently become unnavigable for bots but not players.
	mesh.cell_size = 0.2
	mesh.cell_height = 0.05
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1  # world only
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_geometry_root.navigation_mesh = mesh
	_geometry_root.bake_navigation_mesh(false)

## A 1 m world-space grid on everything. This is not decoration: without a
## regular reference you cannot perceive speed, and "does this feel fast?" is
## the single most important question this level has to answer.
func _build_materials() -> void:
	# Darker grid lines than you would expect: they are the only cue for speed
	# and distance, and a low-contrast grid washes out entirely under sky
	# ambient once the tonemapper has had its way.
	var grid := _make_grid_texture(64, 2, Color(1, 1, 1), Color(0.34, 0.35, 0.40))
	_mat_floor = _make_material(grid, Color(0.40, 0.41, 0.44))
	_mat_wall = _make_material(grid, Color(0.26, 0.28, 0.34))
	_mat_step = _make_material(grid, Color(0.78, 0.46, 0.16))
	_mat_jump = _make_material(grid, Color(0.22, 0.44, 0.74))
	_mat_ramp = _make_material(grid, Color(0.28, 0.60, 0.37))
	_mat_blocked = _make_material(grid, Color(0.68, 0.22, 0.24))
	_mat_slide = _make_material(grid, Color(0.50, 0.34, 0.72))

func _make_grid_texture(size: int, line_px: int, base: Color, line: Color) -> ImageTexture:
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(base)
	for i in size:
		for j in line_px:
			img.set_pixel(i, j, line)
			img.set_pixel(j, i, line)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_material(tex: Texture2D, color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	# World-space triplanar keeps the grid continuous across every box and
	# correctly scaled on rotated ramps, with no UV work per object.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE
	mat.roughness = 0.9
	mat.metallic_specular = 0.35
	return mat

# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

func _box(box_name: String, size: Vector3, pos: Vector3, mat: Material,
		rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	body.rotation_degrees = rot_deg
	body.collision_layer = 1  # world
	body.collision_mask = 0   # static geometry never needs to detect anything

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	_geometry_root.add_child(body)
	return body

## Dimension annotation. Sized to be readable at 5-15 m without covering the
## thing it is annotating -- roughly 17 cm per character, against a player who
## is 1.8 m tall.
func _label(text: String, pos: Vector3, color: Color = Color(1, 1, 1),
		size_scale: float = 1.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = 40
	label.pixel_size = 0.0042 * size_scale
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.fixed_size = false
	label.no_depth_test = false
	_geometry_root.add_child(label)
	return label

## Section heading. Larger than a dimension label so the eye can find sections
## from across the arena.
func _heading(text: String, pos: Vector3, color: Color = Color(1, 1, 1)) -> Label3D:
	return _label(text, pos, color, 1.8)

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.38, 0.55)
	sky_mat.sky_horizon_color = Color(0.62, 0.68, 0.74)
	sky_mat.ground_bottom_color = Color(0.14, 0.15, 0.17)
	sky_mat.ground_horizon_color = Color(0.40, 0.41, 0.44)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	# SSAO exists only on Forward+. The browser build runs the Compatibility
	# renderer, which has no RenderingDevice -- ask for SSAO there and Godot
	# just logs a warning every launch.
	if RenderingServer.get_rendering_device() != null:
		env.ssao_enabled = true
		env.ssao_intensity = 1.0

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_geometry_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	_geometry_root.add_child(sun)

func _build_shell() -> void:
	var half := ARENA_SIZE * 0.5
	_box("Floor", Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), Vector3(0, -0.5, 0), _mat_floor)
	_box("WallNorth", Vector3(ARENA_SIZE, WALL_HEIGHT, 1.0),
			Vector3(0, WALL_HEIGHT * 0.5, -half), _mat_wall)
	_box("WallSouth", Vector3(ARENA_SIZE, WALL_HEIGHT, 1.0),
			Vector3(0, WALL_HEIGHT * 0.5, half), _mat_wall)
	_box("WallWest", Vector3(1.0, WALL_HEIGHT, ARENA_SIZE),
			Vector3(-half, WALL_HEIGHT * 0.5, 0), _mat_wall)
	_box("WallEast", Vector3(1.0, WALL_HEIGHT, ARENA_SIZE),
			Vector3(half, WALL_HEIGHT * 0.5, 0), _mat_wall)

## A measured straight lane. Sprint it and count: at 9 m/s the 30 m mark should
## arrive in about 3.3 s. This is how you tell "fast" from "feels fast".
func _build_distance_lane() -> void:
	_heading("SPRINT LANE ->", Vector3(0, 2.6, -3.0), Color(1, 0.9, 0.5))
	for metres in [5, 10, 15, 20, 25, 30]:
		var z := -float(metres)
		_box("LaneMark%d" % metres, Vector3(3.0, 0.04, 0.2),
				Vector3(0, 0.02, z), _mat_step)
		_label("%d m" % metres, Vector3(2.4, 1.1, z), Color(1, 0.85, 0.55))

## Single ledges bracketing max_step_height (0.35 m by default). 0.20-0.35
## should be walked over without a jump; 0.40 should stop you dead.
func _build_step_ledges() -> void:
	_heading("STEP-UP LIMIT", Vector3(8.0, 2.6, 5.0), Color(1, 0.75, 0.4))
	var heights := [0.20, 0.30, 0.35, 0.40]
	for i in heights.size():
		var h: float = heights[i]
		var x := 5.0 + float(i) * 4.0
		var mat := _mat_blocked if h > 0.35 else _mat_step
		_box("StepLedge%d" % i, Vector3(3.0, h, 3.0), Vector3(x, h * 0.5, 8.0), mat)
		_label("%.2f m" % h, Vector3(x, h + 1.0, 6.2),
				Color(1, 0.5, 0.5) if h > 0.35 else Color(1, 0.85, 0.6))

## Four flights. The 0.35 m flight sits exactly on the step limit and the
## 0.45 m flight is deliberately impossible -- both are boundary tests, and
## boundaries are where stair code breaks.
func _build_staircases() -> void:
	_heading("STAIRCASES", Vector3(15.0, 3.6, -4.0), Color(1, 0.75, 0.4))
	var rises := [0.15, 0.25, 0.35, 0.45]
	var run := 0.4
	var steps := 8
	for i in rises.size():
		var rise: float = rises[i]
		var x := 8.0 + float(i) * 5.5
		var mat := _mat_blocked if rise > 0.35 else _mat_step
		for s in steps:
			var h := rise * float(s + 1)
			var z := -8.0 - run * float(s)
			_box("Stair%d_%d" % [i, s], Vector3(4.0, h, run),
					Vector3(x, h * 0.5, z), mat)
		# Landing. Butt it against the last step's far edge -- computing this
		# from the step count rather than eyeballing an offset is what stops a
		# 0.2 m trip hazard appearing at the top of the flight.
		var top := rise * float(steps)
		var last_edge := -8.0 - run * float(steps) + run * 0.5
		_box("StairTop%d" % i, Vector3(4.0, top, 4.0),
				Vector3(x, top * 0.5, last_edge - 2.0), mat)
		_label("rise %.2f m" % rise, Vector3(x, 1.2, -6.4),
				Color(1, 0.5, 0.5) if rise > 0.35 else Color(1, 0.85, 0.6))

## Ledges around the theoretical jump apex (1.11 m at the default tuning).
## If 1.10 is comfortably clearable and 1.40 is not, gravity and jump_velocity
## agree with each other.
func _build_jump_heights() -> void:
	_heading("JUMP HEIGHT", Vector3(30.0, 3.2, -6.0), Color(0.6, 0.8, 1))
	var heights := [0.60, 0.90, 1.10, 1.25, 1.40]
	for i in heights.size():
		var h: float = heights[i]
		var z := -4.0 + float(i) * 4.5
		_box("JumpPad%d" % i, Vector3(3.5, h, 3.5), Vector3(30.0, h * 0.5, z), _mat_jump)
		_label("%.2f m" % h, Vector3(27.6, h + 1.0, z), Color(0.7, 0.85, 1))

## Increasing gaps at a fixed height. Measures jump *distance*, which is where
## walk speed, sprint speed and air control all show up at once.
func _build_gap_walkway() -> void:
	var y := 2.0
	var width := 3.5
	_heading("GAP JUMPS", Vector3(6.0, 4.6, 16.0), Color(0.6, 0.8, 1))

	# Access stairs up to the walkway.
	for s in 6:
		var h := 0.33 * float(s + 1)
		_box("GapAccess%d" % s, Vector3(3.0, h, 0.5),
				Vector3(2.0, h * 0.5, 20.0 - 0.5 * float(s)), _mat_jump)

	var x := 2.0
	var gaps := [2.0, 3.0, 4.0, 5.0, 6.0]
	for i in gaps.size() + 1:
		_box("GapBlock%d" % i, Vector3(4.0, y, width), Vector3(x + 2.0, y * 0.5, 16.0), _mat_jump)
		x += 4.0
		if i < gaps.size():
			var gap: float = gaps[i]
			_label("%.0f m" % gap, Vector3(x + gap * 0.5, y + 1.4, 16.0), Color(0.7, 0.85, 1))
			x += gap

## 15 / 30 / 45 degrees are walkable; 55 is past floor_max_angle and must
## reject the player rather than letting them creep up it.
func _build_ramps() -> void:
	_heading("RAMPS", Vector3(-14.0, 3.6, 14.0), Color(0.5, 0.9, 0.6))
	var specs := [
		{"angle": 15.0, "length": 10.0},
		{"angle": 30.0, "length": 8.0},
		{"angle": 45.0, "length": 6.0},
		{"angle": 55.0, "length": 6.0},
	]
	var thickness := 0.6
	for i in specs.size():
		var angle: float = specs[i]["angle"]
		var length: float = specs[i]["length"]
		var rad := deg_to_rad(angle)
		var rise := length * sin(rad)
		var run := length * cos(rad)
		var x := -6.0 - float(i) * 6.0
		var z_start := 18.0
		var mat := _mat_blocked if angle > 46.0 else _mat_ramp
		# Sink the slab by half its thickness along the surface normal so the
		# low edge meets the floor flush instead of leaving a lip to trip on.
		var centre := Vector3(
			x,
			rise * 0.5 - (thickness * 0.5) / cos(rad),
			z_start + run * 0.5)
		_box("Ramp%d" % i, Vector3(4.0, thickness, length), centre, mat,
				Vector3(-angle, 0.0, 0.0))
		if angle <= 46.0:
			_box("RampTop%d" % i, Vector3(4.0, rise, 3.0),
					Vector3(x, rise * 0.5, z_start + run + 1.5), mat)
		_label("%.0f deg" % angle, Vector3(x, 1.2, z_start - 1.2),
				Color(1, 0.5, 0.5) if angle > 46.0 else Color(0.6, 0.95, 0.7))

## A long shallow slope. Walk up, turn, sprint-crouch down: slide_slope_boost
## should make the return trip meaningfully faster than the climb.
func _build_slide_slope() -> void:
	var angle := 12.0
	var length := 22.0
	var rad := deg_to_rad(angle)
	var rise := length * sin(rad)
	var run := length * cos(rad)
	var thickness := 0.8
	var x := -25.0
	var z_start := 6.0
	_box("SlideSlope", Vector3(7.0, thickness, length),
			Vector3(x, rise * 0.5 - (thickness * 0.5) / cos(rad), z_start - run * 0.5),
			_mat_slide, Vector3(angle, 0.0, 0.0))
	_box("SlideTop", Vector3(7.0, rise, 5.0),
			Vector3(x, rise * 0.5, z_start - run - 2.5), _mat_slide)
	_heading("SLIDE SLOPE %.0f deg" % angle, Vector3(x, 2.4, z_start + 1.5), Color(0.8, 0.7, 1))
	_label("sprint + crouch downhill", Vector3(x, 1.6, z_start + 1.5), Color(0.75, 0.65, 0.95))

## 1.05 m of clearance: too low to stand, and wide enough to slide through at
## speed if the slide keeps the hull short for long enough.
func _build_crouch_tunnel() -> void:
	var clearance := 1.05
	var length := 14.0
	var z := 28.0
	var x := -8.0
	_box("TunnelRoof", Vector3(length, 0.5, 4.0), Vector3(x, clearance + 0.25, z), _mat_slide)
	_box("TunnelWallA", Vector3(length, 2.4, 0.5), Vector3(x, 1.2, z - 2.25), _mat_slide)
	_box("TunnelWallB", Vector3(length, 2.4, 0.5), Vector3(x, 1.2, z + 2.25), _mat_slide)
	_heading("CROUCH TUNNEL %.2f m" % clearance, Vector3(x + length * 0.5 + 2.0, 2.2, z),
			Color(0.8, 0.7, 1))

## Targets at measured distances, so damage falloff and time-to-kill can be
## read off the range rather than guessed at. Each dummy shows its own health,
## and one strafes for tracking practice -- and, in Milestone 5, for testing
## lag compensation against a hitbox that is actually moving.
##
## Runs east along the clear strip by the north wall. The obvious spot -- next
## to the slide slope -- looked fine and was not: the slope's landing platform
## sits exactly on the sightline to the far target, so every "45 m" shot
## actually stopped at 30 m and quietly reported full damage.
func _build_shooting_range() -> void:
	var firing_x := -36.0
	var lane_z := -32.0

	_heading("SHOOTING RANGE", Vector3(firing_x + 6.0, 3.4, lane_z), Color(1, 0.75, 0.45))
	_box("FiringLine", Vector3(0.25, 0.04, 8.0),
			Vector3(firing_x, 0.02, lane_z), _mat_step)

	# distance, lateral offset. Offsets alternate sides and widen so that the
	# sightline to a far target clears every nearer one by at least a metre --
	# in a straight line the closest dummy eats every shot behind it.
	# Depth is reduced to compensate for the offset, so each dummy stands at
	# exactly its labelled distance rather than slightly further.
	for placement in [[10.0, -3.0], [20.0, 4.0], [30.0, -5.0], [45.0, 6.0]]:
		var distance: float = placement[0]
		var offset: float = placement[1]
		var depth := sqrt(maxf(distance * distance - offset * offset, 0.0))
		var dummy := TargetDummy.new()
		dummy.name = "Target%dm" % int(distance)
		dummy.position = Vector3(firing_x + depth, 0.0, lane_z + offset)
		_geometry_root.add_child(dummy)
		_label("%d m" % int(distance),
				Vector3(firing_x + depth, 0.55, lane_z + offset + 1.2),
				Color(1, 0.85, 0.6))

	# Placed beyond the fixed targets and on the centre line, so nothing can
	# block it and it blocks nothing.
	var mover := TargetDummy.new()
	mover.name = "TargetMoving"
	mover.position = Vector3(firing_x + 55.0, 0.0, lane_z)
	mover.patrol_range = 4.0
	mover.patrol_speed = 6.0
	mover.patrol_axis = Vector3.BACK
	_geometry_root.add_child(mover)
	_label("moving  55 m", Vector3(firing_x + 55.0, 2.55, lane_z), Color(0.7, 0.9, 1))

## Something to strafe around. Tight enough spacing that turning while keeping
## speed actually costs something.
func _build_pillars() -> void:
	_heading("STRAFE COURSE", Vector3(-16.0, 3.6, -10.0), Color(1, 1, 1))
	var offsets := [
		Vector2(-10, -8), Vector2(-14, -12), Vector2(-18, -8), Vector2(-22, -13),
		Vector2(-12, -18), Vector2(-17, -21), Vector2(-23, -19), Vector2(-27, -24),
	]
	for i in offsets.size():
		var o: Vector2 = offsets[i]
		_box("Pillar%d" % i, Vector3(1.2, 4.0, 1.2), Vector3(o.x, 2.0, o.y), _mat_wall)
