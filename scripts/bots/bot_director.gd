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
## Which duel room the player is standing in, or -1 for none. The HUD names the
## tier so a verdict after a fight can be about a specific one.
signal duel_room_changed(index: int)
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

## Slot every duel-room bot carries: the rifle. Held constant so the rooms
## differ by difficulty and nothing else.
const DUEL_WEAPON := 1

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

## Keep one bot of each tier alive in its own sealed room in the duel wing.
##
## Separate from the free-roaming roster on purpose. The whole value of those
## rooms is that exactly one bot of exactly one difficulty is in each, so they
## are not part of a count anybody can turn up.
@export var duel_pits_enabled: bool = true

## Free-roaming bots, held to the main arena.
var bots: Array[PlayerController] = []
## One per duel room, index-aligned with [constant ArenaBuilder.DUEL_PITS].
var duel_bots: Array[PlayerController] = []

var _profiles: Array[BotProfile] = []
var _elapsed: float = 0.0
var _spawned: int = 0
var _player_room: int = -1
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

	_maintain_duel_pits()
	_update_duel_room()

func _on_settings_changed() -> void:
	set_bot_count(_settings.bot_count)
	set_difficulty(_settings.bot_difficulty)
	duel_pits_enabled = _settings.duel_bots

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
			if brain.senses != null:
				brain.senses.profile = profile

# ---------------------------------------------------------------------------

func _spawn_one() -> void:
	var bot := _spawn_bot(current_profile(), ArenaBuilder.main_arena_bounds())
	if bot == null:
		return
	bots.append(bot)
	roster_changed.emit(bots.size())

## Keep exactly one live bot of the right tier in each duel room.
##
## Rebuilt rather than reconfigured when the difficulty of a *room* is fixed by
## the room itself: unlike the roaming roster, these never change tier, so there
## is nothing to retune -- only to replace if one is somehow freed.
func _maintain_duel_pits() -> void:
	duel_bots.resize(ArenaBuilder.DUEL_PITS.size())
	for i in ArenaBuilder.DUEL_PITS.size():
		var existing: PlayerController = duel_bots[i]
		if not duel_pits_enabled:
			if is_instance_valid(existing):
				existing.queue_free()
				duel_bots[i] = null
			continue
		if is_instance_valid(existing):
			continue
		var pit: Array = ArenaBuilder.DUEL_PITS[i]
		var profile := _profiles[clampi(int(pit[1]), 0, _profiles.size() - 1)]
		# Every duel bot carries the rifle, deliberately. The rooms exist to
		# compare tiers, and that only works if the tier is the only thing
		# that differs -- a Recruit with a shotgun and a Veteran with a pistol
		# tells you nothing about reaction time. The rifle is also the weapon
		# every other number in the game is balanced against.
		var bot := _spawn_bot(profile, ArenaBuilder.duel_bounds(i), DUEL_WEAPON)
		if bot == null:
			continue
		bot.name = "Duel%s" % String(pit[2]).capitalize()
		duel_bots[i] = bot

## Report which duel room the player is standing in.
func _update_duel_room() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var index := -1
	if player != null:
		index = duel_room_at(player.global_position)
	if index != _player_room:
		_player_room = index
		duel_room_changed.emit(index)

## Index of the duel room containing [param point], or -1.
func duel_room_at(point: Vector3) -> int:
	for i in ArenaBuilder.DUEL_PITS.size():
		var bounds := ArenaBuilder.duel_bounds(i)
		if point.x >= bounds.position.x and point.x <= bounds.end.x \
				and point.z >= bounds.position.z and point.z <= bounds.end.z:
			return i
	return -1

## Display name of a duel room, for the HUD.
static func duel_room_name(index: int) -> String:
	if index < 0 or index >= ArenaBuilder.DUEL_PITS.size():
		return ""
	return String(ArenaBuilder.DUEL_PITS[index][2])

## [param weapon_slot] of -1 takes the next weapon in the rotation; anything
## else forces that slot.
func _spawn_bot(profile: BotProfile, bounds: AABB,
		weapon_slot: int = -1) -> PlayerController:
	if bot_scene == null:
		return null
	var bot := bot_scene.instantiate() as PlayerController
	if bot == null:
		push_error("BotDirector: bot scene root is not a PlayerController.")
		return null
	var spawn := _pick_spawn(bounds)
	# Positioned before entering the tree: PlayerController records its respawn
	# point in _ready(), so a bot added at the origin and moved afterwards would
	# come back to the origin every time it died.
	bot.position = spawn.origin
	bot.rotation.y = spawn.basis.get_euler().y

	var brain := bot.get_node_or_null(^"BotBrain") as BotBrain
	if brain != null:
		brain.profile = profile
		brain.bounds = bounds
		brain.is_confined = true
		brain.weapon_slot_override = (weapon_slot if weapon_slot >= 0
				else WEAPON_ROTATION[_spawned % WEAPON_ROTATION.size()])
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
	return bot

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
	# Back into its own volume, which for a duel bot is its own room. Coming
	# back somewhere else would end the isolation the room exists to provide.
	#
	# Read off the brain rather than from a table here: the brain is the thing
	# that actually enforces the bounds, and a second copy on the director
	# would be one more pair of numbers that can disagree -- and one more
	# dictionary holding a reference to a bot that has been freed.
	var brain := bot.get_node_or_null(^"BotBrain") as BotBrain
	var bounds: AABB = brain.bounds if brain != null and brain.is_confined \
			else ArenaBuilder.main_arena_bounds()
	bot.set_spawn_point(_pick_spawn(bounds))
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
func _pick_spawn(bounds: AABB) -> Transform3D:
	var map := get_world_3d().navigation_map
	# A point inside the volume is the floor of acceptability, so the fallback
	# is the volume's own centre snapped to the mesh rather than the map origin
	# -- which for a duel room would be somewhere else entirely.
	var centre := bounds.get_center()
	var best := NavigationServer3D.map_get_closest_point(
			map, Vector3(centre.x, bounds.position.y + 0.2, centre.z))
	var best_score := -INF
	for _attempt in PLACEMENT_ATTEMPTS:
		# Sampled inside the volume and then snapped to the mesh, rather than
		# sampled from the whole map and filtered. A duel room is about 5% of
		# the navigable area, so filtering would miss it on most attempts and
		# fall back to the room's centre nearly every time -- a spawn point you
		# could set your watch by.
		var wanted := Vector3(
				_rng.randf_range(bounds.position.x, bounds.end.x),
				bounds.position.y + 0.2,
				_rng.randf_range(bounds.position.z, bounds.end.z))
		var point := NavigationServer3D.map_get_closest_point(map, wanted)
		if point == Vector3.ZERO:
			continue   # map not synchronised yet
		if not _inside(bounds, point):
			continue
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

static func _inside(bounds: AABB, point: Vector3) -> bool:
	return point.x >= bounds.position.x and point.x <= bounds.end.x \
			and point.z >= bounds.position.z and point.z <= bounds.end.z

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
