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
## Upper arm and forearm. Two bones, because one straight segment cannot reach
## a foregrip held out in front of the chest without stretching to twice its
## length, and a stretched arm looks worse than no arm at all.
const ARM_SEGMENT := 0.31
## Rest pose used when there is no weapon to hold.
const REST_HAND := [Vector3(0.17, 1.16, -0.26), Vector3(-0.17, 1.16, -0.26)]

@export var controller_path: NodePath = ^".."

var _controller: PlayerController

var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
## Shoulder, elbow and the two meshes per arm, index 0 right and 1 left.
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _root: Node3D
## Whatever this character is holding, found by the method it answers rather
## than by its class -- see [method _find_weapon].
var _weapon: Node = null

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
	# Right arm first: index 0 is the trigger hand, index 1 the support hand,
	# matching the order grip_points() returns.
	for side in [1.0, -1.0]:
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

## Shoulder -> upper arm -> elbow -> forearm, mirroring the legs.
##
## Built jointed rather than posed, because the hands are solved onto the
## weapon's own grips every frame. A fixed pose can only ever be right for one
## weapon held in one place; this is right for a pistol and a sniper rifle
## without either being a special case.
func _build_arm(side: float, body_size: Vector3) -> void:
	var colour := CharacterHitboxes.base_color(&"body").darkened(0.22)
	var shoulder := Node3D.new()
	shoulder.name = "Shoulder%s" % ("L" if side < 0.0 else "R")
	shoulder.position = Vector3(side * (body_size.x * 0.5 - 0.01),
			SHOULDER_HEIGHT, 0.0)
	_root.add_child(shoulder)
	var upper := _slab("Upper", Vector3(0.11, ARM_SEGMENT, 0.11),
			Vector3(0.0, -ARM_SEGMENT * 0.5, 0.0), colour)
	shoulder.add_child(upper)

	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0.0, -ARM_SEGMENT, 0.0)
	shoulder.add_child(elbow)
	var fore := _slab("Fore", Vector3(0.095, ARM_SEGMENT, 0.095),
			Vector3(0.0, -ARM_SEGMENT * 0.5, 0.0), colour.darkened(0.08))
	elbow.add_child(fore)

	_shoulders.append(shoulder)
	_elbows.append(elbow)
	_upper_arms.append(upper)
	_forearms.append(fore)

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
	_solve_arms()
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

# --- arms -------------------------------------------------------------------

## Put both hands on the weapon.
##
## Solved every frame rather than posed once, because the weapon is parented to
## the head and therefore pitches with aim: a fixed arm pose would hold the
## grips only while the character was looking dead level, and let go the moment
## it looked up or down.
func _solve_arms() -> void:
	if _shoulders.size() < 2:
		return
	var targets: Array = REST_HAND.map(func(p: Vector3) -> Vector3:
			return _root.to_global(p))
	var weapon := _find_weapon()
	if weapon != null:
		var grips: Array = weapon.call(&"grip_points")
		if grips.size() >= 2:
			targets = grips
	for i in 2:
		_solve_arm(i, targets[i])

## Two-bone IK. Both bones are the same length, which collapses the usual law
## of cosines into something much shorter: the elbow angle depends only on how
## far away the target is.
func _solve_arm(index: int, target: Vector3) -> void:
	var shoulder := _shoulders[index]
	var parent := shoulder.get_parent() as Node3D
	var local := parent.to_local(target) - shoulder.position
	var reach := local.length()
	if reach < 0.02:
		return
	# Clamped just short of straight. At exactly full reach the elbow angle is
	# zero and the arm snaps between bent and locked as the target drifts.
	var span := ARM_SEGMENT * 2.0
	reach = clampf(reach, span * 0.25, span * 0.985)
	var direction := local.normalized()

	# Elbow bends backwards and slightly outward, which is where a human one
	# goes and, more usefully, is never in front of the chest.
	var side := 1.0 if index == 0 else -1.0
	var pole := (Vector3(side * 0.45, -0.25, 1.0)).normalized()
	var bend_axis := direction.cross(pole)
	if bend_axis.length_squared() < 0.0001:
		bend_axis = direction.cross(Vector3.UP)
	bend_axis = bend_axis.normalized()

	# Half the interior angle at the shoulder, from the isoceles triangle the
	# two equal bones make with the shoulder-to-target line.
	var half := acos(clampf(reach / span, -1.0, 1.0))
	var upper_direction := direction.rotated(bend_axis, half)

	shoulder.basis = _aim_down(upper_direction)
	# The forearm closes back onto the target by twice that angle.
	_elbows[index].basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(
			shoulder.basis.inverse() * bend_axis, -2.0 * half)

## A basis whose local -Y points along [param direction], because every limb
## segment in this figure hangs downward from its joint.
func _aim_down(direction: Vector3) -> Basis:
	var y := -direction.normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	return Basis(x, y, x.cross(y))

## Anything on this character that can say where its hands should be. Matched by
## method rather than by class so this file, which is generic character code,
## does not have to know that bots exist.
func _find_weapon() -> Node:
	if _weapon != null and is_instance_valid(_weapon):
		return _weapon
	_weapon = null
	for node in _controller.find_children("*", "", true, false):
		if node.has_method(&"grip_points"):
			_weapon = node
			break
	return _weapon

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
