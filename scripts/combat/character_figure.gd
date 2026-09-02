class_name CharacterFigure
extends Node3D
## The visible, animated body of a character.
##
## Bots used to be drawn by making their hitboxes visible. That is honest, but
## a hitbox is one box per region and boxes do not have knees -- so a bot
## crossing the arena at 6.5 m/s was a block sliding along the floor, which
## reads as broken rather than as fast. This builds a jointed figure over the
## same numbers instead.
##
## What matches the hitboxes and what does not, deliberately:
##
## - **Torso and head sit exactly on their hitboxes and never move.** No bob, no
##   lean. That is where nearly every shot goes, so what you see there is
##   exactly what you hit, which is the property worth protecting.
## - **Legs animate**, and a leg swung through a stride reaches outside the legs
##   hitbox. They are worth 0.8x damage and are the hardest thing to hit on
##   purpose, so trading a little precision there for a body that visibly walks
##   is the right way round.
## - **Arms and the weapon are cosmetic.** They are not shootable, in this game
##   or in most others.
##
## Driven entirely by the controller's real state -- speed, whether it is on the
## floor, whether it is alive -- so there is nothing to keep in sync and no
## animation state that can disagree with the physics.

## Metres of travel per complete gait cycle: two strides, matching the footstep
## stride so the legs and the footfalls land together.
const GAIT_DISTANCE := 4.3
## Hip swing at full sprint. Beyond about this the legs read as running rather
## than sprinting and start scissoring through each other.
const MAX_SWING_DEGREES := 34.0
## How far the knee folds at the back of the stride.
const MAX_KNEE_DEGREES := 46.0
## Legs settle back to standing this fast when the character stops.
const SETTLE_SPEED := 6.0

const LEG_HALF_WIDTH := 0.125
const HIP_HEIGHT := 0.90
const SEGMENT := 0.45
const SHOULDER_HEIGHT := 1.46

@export var controller_path: NodePath = ^".."

var _controller: PlayerController

var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _root: Node3D

## Position in the gait cycle, in radians. Advanced by distance travelled rather
## than by time, so the legs stay in step at any speed -- the same reason the
## footsteps and the camera bob are.
var _cycle: float = 0.0
## Eased swing amplitude, so starting and stopping is not a snap.
var _swing: float = 0.0

func _ready() -> void:
	_controller = get_node_or_null(controller_path) as PlayerController
	_build()

func _build() -> void:
	_root = Node3D.new()
	_root.name = "Figure"
	add_child(_root)

	var body_size: Vector3 = CharacterHitboxes.PARTS[1][1]
	var head_size: Vector3 = CharacterHitboxes.PARTS[2][1]
	var legs_size: Vector3 = CharacterHitboxes.PARTS[0][1]

	# Torso and head straight off the hitbox table, at the hitbox heights.
	_root.add_child(_slab("Torso", body_size,
			Vector3(0.0, float(CharacterHitboxes.PARTS[1][2]), 0.0),
			CharacterHitboxes.base_color(&"body")))
	var head := _slab("Head", head_size,
			Vector3(0.0, float(CharacterHitboxes.PARTS[2][2]), 0.0),
			CharacterHitboxes.base_color(&"head"))
	_root.add_child(head)
	head.add_child(CharacterHitboxes.make_visor(head_size))

	for side in [-1.0, 1.0]:
		_build_leg(side, legs_size)
		_build_arm(side, body_size)

## Hip -> thigh -> knee -> shin. Two joints is the minimum that reads as a walk:
## with one, the whole leg pivots rigidly and the foot swings through the floor.
func _build_leg(side: float, legs_size: Vector3) -> void:
	var hip := Node3D.new()
	hip.name = "Hip%s" % ("L" if side < 0.0 else "R")
	hip.position = Vector3(side * LEG_HALF_WIDTH, HIP_HEIGHT, 0.0)
	_root.add_child(hip)

	var width := legs_size.x * 0.5 - 0.02
	var colour := CharacterHitboxes.base_color(&"legs").darkened(0.12)
	hip.add_child(_slab("Thigh", Vector3(width, SEGMENT, legs_size.z * 0.86),
			Vector3(0.0, -SEGMENT * 0.5, 0.0), colour))

	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(0.0, -SEGMENT, 0.0)
	hip.add_child(knee)
	knee.add_child(_slab("Shin", Vector3(width * 0.9, SEGMENT, legs_size.z * 0.8),
			Vector3(0.0, -SEGMENT * 0.5, 0.0), colour.darkened(0.1)))

	_hips.append(hip)
	_knees.append(knee)

## One segment per arm, angled forward *and inward* so both hands converge on
## the weapon. Bots hold a rifle in both hands, so the arms do not swing.
##
## The inward tilt is the difference between a figure holding something and a
## scarecrow: without it the arms hang parallel at shoulder width, pointing at
## nothing, and the weapon appears to float beside one of them.
func _build_arm(side: float, body_size: Vector3) -> void:
	var shoulder := Node3D.new()
	shoulder.name = "Shoulder%s" % ("L" if side < 0.0 else "R")
	# Just at the torso edge, not proud of it.
	shoulder.position = Vector3(side * (body_size.x * 0.5 - 0.01),
			SHOULDER_HEIGHT, 0.0)
	shoulder.rotation = Vector3(deg_to_rad(-52.0), 0.0, deg_to_rad(side * 17.0))
	_root.add_child(shoulder)
	shoulder.add_child(_slab("Arm", Vector3(0.11, 0.42, 0.11),
			Vector3(0.0, -0.21, 0.0),
			CharacterHitboxes.base_color(&"body").darkened(0.22)))
	_arms.append(shoulder)

func _slab(slab_name: String, size: Vector3, offset: Vector3,
		colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = slab_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.75
	mesh.material_override = material
	return mesh

func _process(delta: float) -> void:
	if _controller == null or _hips.size() < 2:
		return
	if _controller.is_dead:
		_animate_death(delta)
		return
	_root.rotation.x = move_toward(_root.rotation.x, 0.0, delta * 6.0)

	var speed := _controller.get_horizontal_speed()
	var grounded := _controller.is_on_floor()
	var reference: float = maxf(_controller.config.sprint_speed, 0.001)
	var target_swing := 0.0
	if grounded and speed > 0.4:
		target_swing = deg_to_rad(MAX_SWING_DEGREES) * clampf(speed / reference, 0.0, 1.15)
		_cycle = wrapf(_cycle + (speed * delta / GAIT_DISTANCE) * TAU, 0.0, TAU)
	elif grounded:
		# Ease the cycle back to a standing pose rather than freezing mid-stride,
		# which leaves a bot standing still with one leg out in front.
		_cycle = move_toward(_cycle, 0.0 if _cycle < PI else TAU, delta * 4.0)
	_swing = move_toward(_swing, target_swing, delta * SETTLE_SPEED)

	if not grounded:
		_animate_airborne(delta)
		return

	for i in 2:
		var phase := _cycle + (0.0 if i == 0 else PI)
		_hips[i].rotation.x = sin(phase) * _swing
		# The knee only folds one way, and only on the back half of the stride
		# -- a knee that bends forwards is the single most obvious tell that a
		# walk cycle was written rather than observed.
		var fold := maxf(-sin(phase + 0.7), 0.0)
		_knees[i].rotation.x = -fold * _swing * (MAX_KNEE_DEGREES / MAX_SWING_DEGREES)

func _animate_airborne(delta: float) -> void:
	# Tucked, with the trailing leg further back. Not a real jump pose, but it
	# is unmistakably not a walk, which is the whole job.
	var rising: bool = _controller.velocity.y > 0.0
	var lead := deg_to_rad(24.0 if rising else 12.0)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		_hips[i].rotation.x = move_toward(_hips[i].rotation.x, lead * side, delta * 5.0)
		_knees[i].rotation.x = move_toward(_knees[i].rotation.x,
				deg_to_rad(-38.0), delta * 5.0)

## Fold up and topple. The hitboxes stay standing, which costs nothing: a dead
## character takes no damage, so there is nothing to be unfair about.
func _animate_death(delta: float) -> void:
	_root.rotation.x = move_toward(_root.rotation.x, deg_to_rad(-82.0), delta * 4.5)
	for i in 2:
		_hips[i].rotation.x = move_toward(_hips[i].rotation.x, deg_to_rad(38.0), delta * 5.0)
		_knees[i].rotation.x = move_toward(_knees[i].rotation.x, deg_to_rad(-62.0), delta * 5.0)
	for arm in _arms:
		arm.rotation.x = move_toward(arm.rotation.x, deg_to_rad(-24.0), delta * 4.0)
