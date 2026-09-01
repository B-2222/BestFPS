class_name BotSenses
extends RefCounted
## What a bot knows, and how it stopped knowing it.
##
## Kept apart from decision-making so the two can be reasoned about separately:
## this file decides whether the bot *can* see you, the states decide what to
## do about it. It is also the file to look at first when a bot behaves
## unfairly, because every way a bot learns anything goes through here.

## Line of sight is traced against world geometry only. Tracing against
## characters too would mean a bot loses sight of you because another bot
## walked past, which reads as the AI blinking.
const SIGHT_MASK := 1

var profile: BotProfile

## Currently visible enemy, or null.
var visible_target: Node3D = null
## Where the target was last seen or heard. Bots hunt this rather than the
## live position -- chasing a position you cannot see is exactly the mistake
## that makes bots feel like they are cheating.
var last_known_position: Vector3 = Vector3.ZERO
var has_last_known: bool = false
## Seconds since the target was last actually seen.
var time_since_seen: float = 999.0
## Counts up while a target is continuously visible; the states compare it to
## the profile's reaction time.
var time_in_view: float = 0.0

var _bot: Node3D
var _eye: Node3D

func _init(bot: Node3D, eye: Node3D, bot_profile: BotProfile) -> void:
	_bot = bot
	_eye = eye
	profile = bot_profile

func update(candidates: Array, delta: float) -> void:
	time_since_seen += delta
	var found: Node3D = null
	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not _is_alive(candidate):
			continue
		if not can_see(candidate):
			continue
		found = candidate
		break

	if found != null:
		visible_target = found
		last_known_position = found.global_position
		has_last_known = true
		time_since_seen = 0.0
		time_in_view += delta
	else:
		visible_target = null
		time_in_view = 0.0
		# Memory expires. A bot that hunts forever never lets you disengage.
		if has_last_known and time_since_seen > profile.memory_seconds:
			has_last_known = false

func can_see(target: Node3D) -> bool:
	var eye := _eye.global_position
	# Aim for the chest rather than the origin: at the feet, a lip of geometry
	# hides a target who is plainly visible.
	var mark := target.global_position + Vector3.UP * 1.2
	var offset := mark - eye
	var distance := offset.length()
	if distance > profile.vision_range:
		return false

	var forward := -_bot.global_transform.basis.z
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.001:
		var angle := rad_to_deg(forward.angle_to(flat.normalized()))
		if angle > profile.view_cone_degrees * 0.5:
			return false

	var space := _bot.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, mark, SIGHT_MASK)
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()

## Gunfire and footsteps. Loudness scales the range, so a shotgun across the
## map carries and a crouched footstep next door does not.
func hear(position: Vector3, loudness: float) -> void:
	var distance := _bot.global_position.distance_to(position)
	if distance > profile.hearing_range * loudness:
		return
	# Heard, not seen: the bot learns roughly where, and has to go and look.
	last_known_position = position
	has_last_known = true
	time_since_seen = minf(time_since_seen, profile.memory_seconds * 0.5)

func _is_alive(candidate: Node) -> bool:
	var health: Node = candidate.get_node_or_null(^"Health")
	return health == null or health.is_alive
