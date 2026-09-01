class_name BotDirector
extends Node3D
## Owns the bot population: how many there are, how good they are, and where
## they come back after they die.
##
## Separate from the bots themselves so that nothing about a bot's behaviour
## depends on how many of them exist. That matters more than it looks: in
## Milestone 5 this is the node that becomes server-only, deciding the roster
## for a lobby of mixed humans and bots, while [BotBrain] runs identically
## whether it is filling a command locally or on a host.

signal roster_changed(count: int)
## Someone killed someone. [param attacker] and [param victim] are the
## character bodies, not their health nodes.
signal fragged(attacker: Node, victim: Node, headshot: bool)

const BOT_SCENE_PATH := "res://scenes/bots/bot.tscn"
const PROFILE_PATHS: Array[String] = [
	"res://assets/config/bots/easy.tres",
	"res://assets/config/bots/normal.tres",
	"res://assets/config/bots/hard.tres",
]

## Never spawn a bot closer than this to a living player. Respawning in
## someone's crosshair is not difficulty, it is a free kill in either
## direction.
const MIN_PLAYER_DISTANCE := 22.0
## Or this close to another bot, so a wave does not arrive stacked in one spot.
const MIN_BOT_DISTANCE := 6.0
## Attempts at finding a point satisfying both before settling for the best of
## a bad set. Bounded because the alternative is a frame-long search on a map
## with nowhere legal to stand.
const PLACEMENT_ATTEMPTS := 24

## Weapon slots handed out around the roster, so a lobby is a mixed bag rather
## than four copies of the same rifle. Rifle-heavy because it is the baseline
## everything else is tuned against.
##
## The sniper is deliberately absent. At 45 rpm and two body shots it is a
## weapon built around one committed decision, and a bot holding one is not a
## fight -- it is a tax on crossing open ground. It goes back in when there is
## a map with sightlines worth denying, which is M4's problem.
const WEAPON_ROTATION: Array[int] = [1, 2, 1, 4, 1, 2, 1, 4, 1, 2, 1, 4]

@export var bot_scene: PackedScene
## Bots wanted in the match. Changing this at runtime adds or removes them.
@export_range(0, 12, 1) var bot_count: int = 3
## Index into [constant PROFILE_PATHS]: 0 easy, 1 normal, 2 hard. Overridden by
## GameSettings whenever that autoload is present, which is everywhere except
## the headless suites.
@export_range(0, 2, 1) var difficulty: int = 0
## Waited out before the first spawn, so the navigation map has been synchronised
## by the server. Spawning into an unsynchronised map places every bot at the
## origin, which looks like the spawner is broken rather than early.
@export var startup_delay: float = 0.35

var bots: Array[PlayerController] = []

var _profiles: Array[BotProfile] = []
var _elapsed: float = 0.0
var _spawned: int = 0
var _rng := RandomNumberGenerator.new()
## The GameSettings autoload, resolved by path rather than by its global name:
## the headless test suites run on a custom SceneTree that has no autoloads, so
## the name would parse fine and be null at run time.
var _settings: Node = null

func _ready() -> void:
	_rng.randomize()
	add_to_group(&"bot_director")
	if bot_scene == null:
		bot_scene = load(BOT_SCENE_PATH) as PackedScene
	for path in PROFILE_PATHS:
		var profile := load(path) as BotProfile
		if profile != null:
			_profiles.append(profile)
	if _profiles.is_empty():
		_profiles.append(BotProfile.new())

	# Settings are read last, deliberately: applying a difficulty index before
	# the profiles exist indexes an empty array.
	_settings = get_node_or_null(^"/root/GameSettings")
	if _settings != null:
		_settings.match_settings_changed.connect(_on_settings_changed)
		_on_settings_changed()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < startup_delay:
		return
	# Prune first: a bot freed by anything other than this director (a level
	# reload, say) must not leave a hole that the count check never notices.
	var alive: Array[PlayerController] = []
	for bot in bots:
		if is_instance_valid(bot):
			alive.append(bot)
	if alive.size() != bots.size():
		bots = alive
		roster_changed.emit(bots.size())

	if bots.size() < bot_count:
		_spawn_one()
	elif bots.size() > bot_count:
		_despawn_one()

func _on_settings_changed() -> void:
	set_bot_count(_settings.bot_count)
	set_difficulty(_settings.bot_difficulty)

func current_profile() -> BotProfile:
	return _profiles[clampi(difficulty, 0, _profiles.size() - 1)]

## Change the roster size. Bots are added or removed one per frame rather than
## in a burst, so a jump from 0 to 12 does not stall the frame that asked for it.
func set_bot_count(count: int) -> void:
	bot_count = clampi(count, 0, 12)

## Retune every bot in place. Difficulty is a [BotProfile] reference and nothing
## caches values out of it, so switching mid-match takes effect on the next tick
## without respawning anyone.
func set_difficulty(index: int) -> void:
	difficulty = clampi(index, 0, _profiles.size() - 1)
	var profile := current_profile()
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		var brain := bot.get_node_or_null(^"BotBrain") as BotBrain
		if brain != null:
			brain.profile = profile
			brain.senses.profile = profile

# ---------------------------------------------------------------------------

func _spawn_one() -> void:
	if bot_scene == null:
		return
	var bot := bot_scene.instantiate() as PlayerController
	if bot == null:
		push_error("BotDirector: bot scene root is not a PlayerController.")
		return
	var spawn := _pick_spawn()
	# Positioned before entering the tree: PlayerController records its respawn
	# point in _ready(), so a bot added at the origin and moved afterwards would
	# come back to the origin every time it died.
	bot.position = spawn.origin
	bot.rotation.y = spawn.basis.get_euler().y

	var brain := bot.get_node_or_null(^"BotBrain") as BotBrain
	if brain != null:
		brain.profile = current_profile()
		brain.weapon_slot_override = WEAPON_ROTATION[
				bots.size() % WEAPON_ROTATION.size()]
	# Numbered from a counter, not from the roster size: after a despawn the
	# size repeats a number that is still in use, and Godot silently mangles
	# the duplicate into something no NodePath will ever match.
	_spawned += 1
	bot.name = "Bot%d" % _spawned
	add_child(bot)
	bot.set_spawn_point(bot.global_transform)

	if bot.health != null:
		bot.health.died.connect(_on_bot_died.bind(bot))
	if bot.weapons != null:
		bot.weapons.killed.connect(_on_kill.bind(bot))

	bots.append(bot)
	roster_changed.emit(bots.size())

func _despawn_one() -> void:
	if bots.is_empty():
		return
	var bot := bots.pop_back() as PlayerController
	if is_instance_valid(bot):
		bot.queue_free()
	roster_changed.emit(bots.size())

## Relocate on death rather than on revive. [Health] emits `revived` and the
## controller respawns from the same signal, so choosing the new point here --
## during the death timer -- guarantees it is in place before the respawn reads
## it, without depending on which listener the engine calls first.
func _on_bot_died(info: DamageInfo, bot: PlayerController) -> void:
	if not is_instance_valid(bot):
		return
	bot.set_spawn_point(_pick_spawn())
	fragged.emit(info.source, bot, info.is_headshot)

## Kills the *player* scores are reported by the player's own weapon controller;
## this handles a bot killing something.
func _on_kill(info: DamageInfo, _bot: PlayerController) -> void:
	# Bot deaths are announced from _on_bot_died so that world damage and
	# friendly fire are covered too. Nothing to do here unless the victim is a
	# player, which has no death hook of its own on this side.
	if info.victim != null and info.victim.is_in_group(&"player"):
		fragged.emit(info.source, info.victim, info.is_headshot)

# --- placement --------------------------------------------------------------

## A spot on the navigation mesh that is not on top of anybody.
##
## Sampled from the navigation map rather than from hand-placed markers,
## because the arena is generated at runtime: markers would have to be kept in
## step with the geometry by hand, and the navigation mesh already knows every
## place a character can legally stand.
func _pick_spawn() -> Transform3D:
	var map := get_world_3d().navigation_map
	var best := Vector3(0.0, 1.0, 0.0)
	var best_score := -INF
	for _attempt in PLACEMENT_ATTEMPTS:
		var point := NavigationServer3D.map_get_random_point(map, 1, false)
		if point == Vector3.ZERO:
			continue   # map not synchronised yet
		var score := _score_spawn(point)
		if score > best_score:
			best_score = score
			best = point
		if score >= MIN_PLAYER_DISTANCE:
			break
	# Lifted clear of the floor: the navigation mesh sits on the surface, and
	# spawning a 1.8 m hull with its origin exactly on it starts it interpenetrating.
	return Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)),
			best + Vector3.UP * 0.15)

## Distance to the nearest character, capped at the point where more distance
## stops being better -- otherwise every bot spawns in the same far corner.
func _score_spawn(point: Vector3) -> float:
	var score := MIN_PLAYER_DISTANCE
	for node in get_tree().get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		score = minf(score, point.distance_to(body.global_position))
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		# Bots crowding each other matters less than crowding the player, so it
		# is scored against a smaller radius rather than excluded outright.
		score = minf(score, point.distance_to(bot.global_position)
				+ (MIN_PLAYER_DISTANCE - MIN_BOT_DISTANCE))
	return score
