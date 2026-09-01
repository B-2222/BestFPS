class_name NoiseEvent
extends RefCounted
## The one place anything audible announces itself to the AI.
##
## Named NoiseEvent, not Noise: Godot already ships a built-in [Noise] class
## (the base of FastNoiseLite). A class_name that collides with a native one is
## not rejected -- it is silently ignored, and every call site then resolves to
## the engine's class and fails with "static function not found", pointing at
## the caller rather than at the name.
##
## Sound reaches bots by a group call rather than a subscription, so a gun does
## not have to know bots exist -- and equally, so that adding a new noisy thing
## later (a grenade, a footstep on metal, a door) is one line here rather than
## a new signal on every listener.
##
## [param loudness] scales the listener's hearing range, so it is "how far this
## carries relative to a rifle shot", not a volume in decibels. Keeping it
## relative means retuning a bot's ears is one number in [BotProfile] instead of
## a pass over every call site.

## [param source] is the character that made the noise, so it can be told apart
## from the ones hearing it.
static func emit(tree: SceneTree, position: Vector3, loudness: float,
		source: Node = null) -> void:
	if tree == null or loudness <= 0.0:
		return
	tree.call_group(&"bots", &"hear_noise", position, loudness, source)
