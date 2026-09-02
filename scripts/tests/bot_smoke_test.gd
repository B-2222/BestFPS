extends SceneTree
## Headless behavioural checks for bots.
##
## Run: godot --headless --path . --script scripts/tests/bot_smoke_test.gd
##
## Most of what makes a bot good is judged by playing against it, but the thing
## that makes a bot *fair* is not: it is a set of claims about what it can know
## and how fast it can act on them, and every one of those is checkable. That is
## what this suite is for. A bot that shoots through a wall, sees you behind it,
## or reacts in one tick is not a difficulty setting, it is a bug -- and it is
## the kind of bug that is very hard to spot by feel, because losing to it feels
## exactly like losing to a good opponent.

const TICK := 1.0 / 120.0

## Somewhere flat with a long clear sightline: the sprint lane runs down the
## middle of the arena with nothing on it taller than a 4 cm distance marker.
const LANE_X := 0.0
## One of the strafe-course pillars, 1.2 m square and 4 m tall, used as the
## thing to hide behind.
const PILLAR := Vector3(-10.0, 0.0, -8.0)

var _arena: Node
var _director: BotDirector
var _player: PlayerController

var _plan: Array = []
var _phase := 0
var _phase_tick := 0
var _failures: PackedStringArray = PackedStringArray()
var _checks := 0
var _wired := false

## Per-phase measurements.
var _ticks_to_engage := -1
var _shots := 0
var _player_hits := 0
var _player_damage := 0.0
var _start_distance := 0.0
var _max_distance := 0.0
var _min_distance := 0.0
var _sweep := 0.0
var _last_yaw := 0.0
var _saw_reload := false
var _fired_during_reload := false
var _shots_at_reload := 0
var _observed_states: Dictionary = {}

func _initialize() -> void:
	_arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	root.add_child(_arena)
	_player = _arena.get_node("Player") as PlayerController
	# This suite is the input source: the player stands still and gets shot at.
	_player.set_input_source(null)
	_director = _arena.get_node("BotDirector") as BotDirector

func _physics_process(delta: float) -> bool:
	if not _wired:
		_wire()
		return false
	if _phase >= _plan.size():
		return _finish()
	var step: Dictionary = _plan[_phase]
	if _phase_tick == 0:
		print("  [%d/%d] %s" % [_phase + 1, _plan.size(), step["name"]])
		if step.has("setup"):
			(step["setup"] as Callable).call()
	_player.cmd.clear()
	if step.has("during"):
		(step["during"] as Callable).call(_phase_tick)
	_phase_tick += 1
	if _phase_tick >= int(step["ticks"]):
		if step.has("check"):
			(step["check"] as Callable).call()
		_phase += 1
		_phase_tick = 0
	return false

func _wire() -> void:
	_wired = true
	if _director == null:
		push_error("bot smoke test: arena has no BotDirector")
		quit(1)
		return
	# Written straight onto the director rather than through GameSettings: the
	# setter persists to the user's settings file, and a test must not edit the
	# developer's preferences to run.
	_director.bot_count = 0
	# The duel rooms hold their own permanent roster, which would show up in
	# every roster-size assertion below and shoot at the player in half the
	# phases. They get their own phase at the end instead.
	_director.duel_pits_enabled = false
	_player.health.damaged.connect(func(info: DamageInfo, _remaining: float) -> void:
		_player_hits += 1
		_player_damage += info.amount)
	_build_plan()
	print("\n=== bot smoke test (%d phases) ===\n" % _plan.size())

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _bot(index: int = 0) -> PlayerController:
	if index >= _director.bots.size():
		return null
	return _director.bots[index]

func _brain(bot: PlayerController) -> BotBrain:
	return bot.get_node_or_null(^"BotBrain") as BotBrain

func _profile(name: String) -> BotProfile:
	return load("res://assets/config/bots/%s.tres" % name) as BotProfile

func _stand_player(position: Vector3) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = position
	_player.machine.transition_to(&"grounded")
	if not _player.health.is_alive:
		_player.health.revive()

## Put a bot somewhere with a clean slate: no memory, no target, full health,
## full magazine, idle. Phases must not inherit each other's state -- the combat
## suite learned that the hard way, where a phase silently ran with the previous
## phase's weapon and passed while testing nothing.
func _place_bot(bot: PlayerController, position: Vector3, yaw: float,
		profile_name: String = "normal") -> void:
	var brain := _brain(bot)
	bot.velocity = Vector3.ZERO
	bot.global_position = position
	bot.yaw = yaw
	bot.pitch = 0.0
	bot.recoil_offset = Vector2.ZERO
	bot.apply_view()
	bot.machine.transition_to(&"grounded")
	if not bot.health.is_alive:
		bot.health.revive()
	bot.health.current = bot.health.max_health

	brain.profile = _profile(profile_name)
	brain.senses.profile = brain.profile
	brain.senses.visible_target = null
	brain.senses.has_last_known = false
	brain.senses.time_since_seen = 999.0
	brain.senses.time_in_view = 0.0
	brain.aim_error = Vector2.ZERO
	brain.fight_commit = 0.0
	brain.machine.transition_to(&"bot_idle")
	var rt := brain.weapon()
	if rt != null:
		rt.magazine = rt.resource.magazine_size
		rt.reserve = rt.resource.reserve_ammo
		rt.phase = WeaponRuntime.Phase.READY
		rt.cooldown_ticks = 0
		rt.shot_index = 0
		rt.spread = 0.0

## Point [param bot] at a world position from wherever it is standing now.
##
## Always called after _place_bot, never as an argument to it: GDScript
## evaluates arguments before the call, so computing the yaw inline aims the
## bot from its *previous* position. That produced a phase where the bot was
## placed facing away from the player and quietly measured nothing at all.
func _look_at(bot: PlayerController, point: Vector3) -> void:
	var to := point - bot.global_position
	bot.yaw = atan2(-to.x, -to.z)
	bot.pitch = 0.0
	bot.apply_view()

func _duel(index: int) -> PlayerController:
	if index >= _director.duel_bots.size():
		return null
	return _director.duel_bots[index]

## Somewhere in the access spine, level with a room's door but outside it.
func _spine_point(room: int) -> Vector3:
	var bounds := ArenaBuilder.duel_bounds(room)
	return Vector3(bounds.position.x - 3.0, 1.0, bounds.get_center().z)

func _all_duel_bots_home() -> bool:
	for i in ArenaBuilder.DUEL_PITS.size():
		var bot := _duel(i)
		if bot == null or not is_instance_valid(bot):
			return false
		if not BotDirector._inside(ArenaBuilder.duel_bounds(i), bot.global_position):
			return false
	return true

func _reset_counters() -> void:
	_ticks_to_engage = -1
	_shots = 0
	_player_hits = 0
	_player_damage = 0.0
	_sweep = 0.0
	_saw_reload = false
	_fired_during_reload = false
	_shots_at_reload = 0
	_observed_states.clear()

## Watch one bot for a phase: record its state, its shots and when it engaged.
func _observe(bot: PlayerController, tick: int) -> void:
	var brain := _brain(bot)
	if brain == null or brain.machine == null:
		return
	var state: StringName = brain.machine.current.id
	_observed_states[state] = int(_observed_states.get(state, 0)) + 1
	if state == &"bot_engage" and _ticks_to_engage < 0:
		_ticks_to_engage = tick

func _count_shot(_weapon: WeaponResource) -> void:
	_shots += 1

func _watch_shots(bot: PlayerController) -> void:
	var weapons := bot.weapons
	if weapons != null and not weapons.fired.is_connected(_count_shot):
		weapons.fired.connect(_count_shot)

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------

func _build_plan() -> void:
	_plan = [
	{
		"name": "difficulty profiles are ordered, easy to hard",
		"ticks": 1,
		"check": func() -> void:
			var easy := _profile("easy")
			var normal := _profile("normal")
			var hard := _profile("hard")
			_expect(easy != null and normal != null and hard != null,
					"all three profiles load")
			# A typo in a .tres is invisible until someone notices that hard
			# feels easier than normal, which could be weeks.
			_expect(easy.reaction_time > normal.reaction_time
					and normal.reaction_time > hard.reaction_time,
					"reaction time falls with difficulty (%.2f > %.2f > %.2f)"
					% [easy.reaction_time, normal.reaction_time, hard.reaction_time])
			_expect(easy.vision_range < normal.vision_range
					and normal.vision_range < hard.vision_range,
					"vision range rises with difficulty")
			_expect(easy.aim_error_degrees > normal.aim_error_degrees
					and normal.aim_error_degrees > hard.aim_error_degrees,
					"aim error falls with difficulty")
			_expect(easy.aim_speed < normal.aim_speed
					and normal.aim_speed < hard.aim_speed,
					"turn speed rises with difficulty"),
	},
	{
		"name": "director spawns the requested roster on the navigation mesh",
		"ticks": 90,
		"setup": func() -> void:
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_director.bot_count = 2,
		"check": func() -> void:
			_expect(_director.bots.size() == 2,
					"roster is 2, got %d" % _director.bots.size())
			var map := _arena.get_viewport().find_world_3d().navigation_map
			for bot in _director.bots:
				var closest := NavigationServer3D.map_get_closest_point(
						map, bot.global_position)
				var flat := Vector2(closest.x - bot.global_position.x,
						closest.z - bot.global_position.z).length()
				_expect(flat < 1.5,
						"%s stands on the navigation mesh (%.2f m off)" % [bot.name, flat])
				_expect(bot.global_position.distance_to(_player.global_position)
						> BotDirector.MIN_BOT_DISTANCE,
						"%s did not spawn on top of the player" % bot.name),
	},
	{
		"name": "roster shrinks when the count is lowered",
		"ticks": 60,
		"setup": func() -> void:
			_director.bot_count = 1,
		"check": func() -> void:
			_expect(_director.bots.size() == 1,
					"roster is 1, got %d" % _director.bots.size()),
	},
	{
		"name": "idle bot scans instead of staring at one wall",
		"ticks": 240,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 30.0))
			# 40 m away and facing the far wall: out of the easy profile's
			# 34 m sight, and pointed the other way besides.
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -10.0), 0.0, "easy")
			_last_yaw = _bot().yaw,
		"during": func(tick: int) -> void:
			# Total travel, not net displacement. The scan reverses on a timer
			# that is not reset by re-entering the state, so a phase that
			# happens to start just before a reversal ends where it began --
			# which is a scanning bot, not a stationary one.
			_sweep += absf(wrapf(_bot().yaw - _last_yaw, -PI, PI))
			_last_yaw = _bot().yaw
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_sweep > 0.8,
					"swept its view while idle (%.2f rad of travel, states %s)"
					% [_sweep, _observed_states])
			_expect(not _observed_states.has(&"bot_engage"),
					"never engaged something it cannot see"),
	},
	{
		"name": "a target behind the bot is not seen until it turns around",
		"ticks": 120,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			# Player 8 m directly behind: well inside every range, outside
			# every view cone. The bot sits at z = -8 and the player at z = 0,
			# so facing the player is yaw PI and facing away is yaw 0.
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -8.0), 0.0, "hard"),
		"during": func(tick: int) -> void:
			var brain := _brain(_bot())
			if tick == 0:
				_expect(brain.senses.can_see(_player) == false,
						"cannot see a target directly behind it")
			# Frozen facing away: the idle scan would eventually find them,
			# and this phase is about the cone, not about the scan.
			_bot().yaw = 0.0
			_bot().apply_view()
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(not _observed_states.has(&"bot_engage"),
					"stayed unaware of a target behind it")
			_bot().yaw = PI
			_bot().apply_view()
			_expect(_brain(_bot()).senses.can_see(_player),
					"sees the same target once turned around"),
	},
	{
		"name": "a wall breaks line of sight",
		"ticks": 240,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			# Player and bot on opposite sides of a 4 m pillar, 4 m each side.
			_stand_player(PILLAR + Vector3(0.0, 1.0, 4.0))
			_place_bot(_bot(), PILLAR + Vector3(0.0, 1.0, -4.0), 0.0, "hard")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			# Held on target for the whole phase, so the only thing that can
			# stop it shooting is the pillar.
			_look_at(_bot(), _player.global_position)
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_brain(_bot()).senses.visible_target == null,
					"target behind a pillar is not visible")
			# The claim that actually matters: not just "did not see", but
			# "did not shoot".
			_expect(_shots == 0, "fired no shots through the pillar, got %d" % _shots),
	},
	{
		"name": "the same target in the open is seen and shot at",
		"ticks": 300,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -12.0), 0.0, "hard")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			# Kept alive so the fight lasts the whole phase rather than ending
			# the moment the bot wins it.
			_player.health.heal(100.0)
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_observed_states.has(&"bot_engage"), "engaged a visible target")
			_expect(_shots > 0, "fired at it (%d shots)" % _shots)
			_expect(_player_hits > 0, "hit the player (%d hits, %.0f damage)"
					% [_player_hits, _player_damage]),
	},
	{
		"name": "reaction time is spent before the first shot",
		"ticks": 200,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -14.0), 0.0, "normal")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			_observe(_bot(), tick),
		"check": func() -> void:
			var profile := _profile("normal")
			var expected := int(profile.reaction_time / TICK)
			_expect(_ticks_to_engage >= expected - 2,
					"waited %d ticks before engaging, expected about %d"
					% [_ticks_to_engage, expected])
			_expect(_ticks_to_engage <= expected + 12,
					"engaged within a reasonable margin of its reaction time (%d vs %d)"
					% [_ticks_to_engage, expected]),
	},
	{
		"name": "a harder bot reacts faster than an easier one",
		"ticks": 200,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -14.0), 0.0, "hard")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			_observe(_bot(), tick),
		"check": func() -> void:
			var hard := int(_profile("hard").reaction_time / TICK)
			_expect(_ticks_to_engage >= hard - 2 and _ticks_to_engage <= hard + 12,
					"veteran engaged in %d ticks, expected about %d"
					% [_ticks_to_engage, hard]),
	},
	{
		"name": "fire rate is the weapon's, not the bot's",
		"ticks": 480,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -14.0), 0.0, "hard")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			_observe(_bot(), tick),
		"check": func() -> void:
			# 480 ticks is 4 s. The rifle is 600 rpm, so 40 rounds is the
			# ceiling even holding the trigger down through the whole phase.
			var rt := _brain(_bot()).weapon()
			var ceiling := int(4.0 * rt.resource.rounds_per_minute / 60.0) + 1
			_expect(_shots <= ceiling,
					"fired %d rounds in 4 s, weapon ceiling is %d" % [_shots, ceiling])
			_expect(_shots > 0, "did fire (%d)" % _shots),
	},
	{
		"name": "aim error means a bot misses sometimes",
		"ticks": 600,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			# Long range, easy profile: the error model should be plainly
			# visible here. If this ever reports a perfect record, aim error
			# has stopped being applied.
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -30.0), 0.0, "easy")
			_look_at(_bot(), _player.global_position),
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_shots >= 5, "took enough shots to judge (%d)" % _shots)
			_expect(_player_hits < _shots,
					"missed at least one of %d shots (%d hits)" % [_shots, _player_hits]),
	},
	{
		"name": "gunfire is heard through a wall, and investigated",
		"ticks": 300,
		"setup": func() -> void:
			_reset_counters()
			# Facing away, behind the pillar, with the player well out of the
			# easy profile's sight: the only way it can learn anything is by
			# hearing it.
			_stand_player(PILLAR + Vector3(0.0, 1.0, 6.0))
			_place_bot(_bot(), PILLAR + Vector3(0.0, 1.0, -6.0), PI, "easy")
			_start_distance = _bot().global_position.distance_to(
					_player.global_position),
		"during": func(tick: int) -> void:
			if tick == 30:
				NoiseEvent.emit(self, _player.global_position, 1.0)
				_expect(_brain(_bot()).senses.has_last_known,
						"a gunshot inside hearing range seeds a last-known position")
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_observed_states.has(&"bot_hunt"),
					"went to investigate the noise")
			var now := _bot().global_position.distance_to(_player.global_position)
			_expect(now < _start_distance - 1.0,
					"closed on the noise (%.1f m -> %.1f m)" % [_start_distance, now]),
	},
	{
		"name": "a noise beyond hearing range is ignored",
		"ticks": 30,
		"setup": func() -> void:
			_reset_counters()
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -10.0), 0.0, "easy"),
		"during": func(tick: int) -> void:
			if tick == 5:
				# The easy profile hears 26 m; this is 200 m away.
				NoiseEvent.emit(self,
						_bot().global_position + Vector3(200.0, 0.0, 0.0), 1.0),
		"check": func() -> void:
			_expect(not _brain(_bot()).senses.has_last_known,
					"did not hear a shot 200 m away"),
	},
	{
		"name": "memory of a lost target expires",
		"ticks": 600,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -10.0), 0.0, "easy")
			var brain := _brain(_bot())
			# Seed a memory, then take the target away entirely.
			brain.senses.last_known_position = _player.global_position
			brain.senses.has_last_known = true
			brain.senses.time_since_seen = 0.0
			_stand_player(Vector3(LANE_X, 1.0, 200.0)),
		"during": func(tick: int) -> void:
			_observe(_bot(), tick),
		"check": func() -> void:
			var brain := _brain(_bot())
			_expect(not brain.senses.has_last_known,
					"forgot a target it has not seen for %.1f s"
					% brain.profile.memory_seconds)
			_expect(_observed_states.has(&"bot_idle"),
					"went back to idle after giving up"),
	},
	{
		"name": "a bot reloads rather than fighting on an empty magazine",
		"ticks": 900,
		"setup": func() -> void:
			_reset_counters()
			_watch_shots(_bot())
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -12.0), 0.0, "hard")
			_look_at(_bot(), _player.global_position)
			var rt := _brain(_bot()).weapon()
			rt.magazine = 2,
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			var rt := _brain(_bot()).weapon()
			if rt.phase == WeaponRuntime.Phase.RELOADING:
				_saw_reload = true
				if _shots != _shots_at_reload:
					_fired_during_reload = true
			else:
				_shots_at_reload = _shots
			_observe(_bot(), tick),
		"check": func() -> void:
			var rt := _brain(_bot()).weapon()
			_expect(_saw_reload, "started a reload")
			_expect(not _fired_during_reload, "fired nothing mid-reload")
			_expect(rt.magazine > 2,
					"magazine refilled (%d rounds, states %s)"
					% [rt.magazine, _observed_states]),
	},
	{
		"name": "a hurt bot backs off, then commits instead of dithering",
		"ticks": 700,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -12.0), 0.0, "normal")
			_look_at(_bot(), _player.global_position)
			var bot := _bot()
			# Just under the normal profile's 30% retreat threshold.
			bot.health.current = bot.health.max_health * 0.25
			_start_distance = bot.global_position.distance_to(_player.global_position)
			_max_distance = _start_distance,
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			# Held down: regeneration would lift it back over the threshold
			# mid-phase and this is a test of the decision, not of the timer.
			var bot := _bot()
			bot.health.current = minf(bot.health.current, bot.health.max_health * 0.25)
			_max_distance = maxf(_max_distance,
					bot.global_position.distance_to(_player.global_position))
			_observe(bot, tick),
		"check": func() -> void:
			_expect(_observed_states.has(&"bot_retreat"),
					"retreated when hurt")
			_expect(_max_distance > _start_distance + 1.5,
					"actually gave ground (%.1f m -> %.1f m)"
					% [_start_distance, _max_distance])
			var retreat_ticks: int = int(_observed_states.get(&"bot_retreat", 0))
			# Without the commit timer a bot on the threshold flips back into
			# retreating every few ticks and spends the whole phase there.
			_expect(retreat_ticks < 700,
					"did not spend the whole fight retreating (%d of 700 ticks)"
					% retreat_ticks)
			_expect(_observed_states.has(&"bot_engage"),
					"came back and fought"),
	},
	{
		"name": "a killed bot respawns somewhere else",
		"ticks": 720,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(LANE_X, 1.0, 0.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -12.0), 0.0, "normal")
			_start_distance = 0.0
			var bot := _bot()
			var info := DamageInfo.new()
			info.amount = bot.health.max_health * 2.0
			info.source = _player
			info.victim = bot
			bot.health.apply_damage(info),
		"during": func(tick: int) -> void:
			if tick == 1:
				_expect(not _bot().health.is_alive, "died when killed")
				_expect(_bot().is_dead, "controller knows it is dead"),
		"check": func() -> void:
			var bot := _bot()
			_expect(bot.health.is_alive, "revived")
			_expect(not bot.is_dead, "controller is playable again")
			_expect(bot.global_position.distance_to(Vector3(LANE_X, 1.0, -12.0)) > 5.0,
					"respawned away from where it died")
			_expect(bot.global_position.distance_to(_player.global_position)
					> BotDirector.MIN_BOT_DISTANCE,
					"did not respawn in the player's lap"),
	},
	{
		"name": "a bot walks a navigation path to a distant goal",
		"ticks": 900,
		"setup": func() -> void:
			_reset_counters()
			# Player parked far away so nothing distracts it from walking.
			_stand_player(Vector3(34.0, 1.0, 34.0))
			_place_bot(_bot(), Vector3(LANE_X, 1.0, -28.0), 0.0, "easy")
			var brain := _brain(_bot())
			var goal := Vector3(LANE_X, 0.0, 2.0)
			brain.senses.last_known_position = goal
			brain.senses.has_last_known = true
			brain.senses.time_since_seen = 0.0
			brain.machine.transition_to(&"bot_hunt")
			_start_distance = _bot().global_position.distance_to(goal)
			_min_distance = _start_distance,
		"during": func(tick: int) -> void:
			var brain := _brain(_bot())
			# The memory would expire long before it arrives, and this phase is
			# about walking, not about remembering.
			brain.senses.time_since_seen = 0.0
			brain.senses.has_last_known = true
			_min_distance = minf(_min_distance,
					_bot().global_position.distance_to(Vector3(LANE_X, 0.0, 2.0)))
			_observe(_bot(), tick),
		"check": func() -> void:
			_expect(_start_distance > 25.0,
					"started far enough away to be a real path (%.1f m)" % _start_distance)
			_expect(_min_distance < 3.0,
					"walked the path and arrived (%.1f m -> %.1f m, ended at %s, states %s)"
					% [_start_distance, _min_distance,
						str(_bot().global_position.round()), _observed_states]),
	},
	{
		"name": "bots fight each other, not just the player",
		"ticks": 900,
		"setup": func() -> void:
			_reset_counters()
			_director.bot_count = 2,
		"during": func(tick: int) -> void:
			# Both bots parked in sight of each other, player far away.
			if tick == 60 and _director.bots.size() >= 2:
				_stand_player(Vector3(34.0, 1.0, 34.0))
				var a := _bot(0)
				var b := _bot(1)
				_place_bot(a, Vector3(LANE_X, 1.0, -8.0), 0.0, "hard")
				_place_bot(b, Vector3(LANE_X, 1.0, -20.0), 0.0, "hard")
				_look_at(a, b.global_position)
				_look_at(b, a.global_position)
				_watch_shots(a)
				_watch_shots(b)
				_start_distance = a.health.current + b.health.current,
		"check": func() -> void:
			_expect(_director.bots.size() >= 2, "two bots present")
			var total: float = _bot(0).health.current + _bot(1).health.current
			_expect(_shots > 0, "shots were fired between them (%d)" % _shots)
			_expect(total < _start_distance,
					"they damaged each other (%.0f hp -> %.0f hp)"
					% [_start_distance, total]),
	},
	{
		"name": "duel wing puts one bot of each tier in its own room",
		"ticks": 240,
		"setup": func() -> void:
			_reset_counters()
			# Well away from all three, so nothing is fighting while the wing
			# fills and the roster can be counted at rest.
			_stand_player(Vector3(0.0, 1.0, 0.0))
			_director.bot_count = 0
			_director.duel_pits_enabled = true,
		"check": func() -> void:
			_expect(_director.duel_bots.size() == ArenaBuilder.DUEL_PITS.size(),
					"one bot per room (%d of %d)"
					% [_director.duel_bots.size(), ArenaBuilder.DUEL_PITS.size()])
			for i in ArenaBuilder.DUEL_PITS.size():
				var bot := _duel(i)
				_expect(bot != null and is_instance_valid(bot),
						"room %d is occupied" % i)
				if bot == null:
					continue
				var bounds := ArenaBuilder.duel_bounds(i)
				_expect(BotDirector._inside(bounds, bot.global_position),
						"%s spawned inside its own room" % bot.name)
				var brain := _brain(bot)
				var wanted: String = ["Recruit", "Regular", "Veteran"][i]
				_expect(brain.profile.display_name == wanted,
						"room %d holds a %s, got %s"
						% [i, wanted, brain.profile.display_name])
				# The rooms are only a fair comparison if the tier is the one
				# thing that changes between them.
				var rt := brain.weapon()
				_expect(rt != null and rt.resource.slot == BotDirector.DUEL_WEAPON,
						"room %d carries the same weapon as the others (%s)"
						% [i, "none" if rt == null else rt.resource.display_name]),
	},
	{
		"name": "a bot in one room cannot see the corridor outside another",
		"ticks": 120,
		"setup": func() -> void:
			_reset_counters()
			# Standing in the spine outside the Recruit room, which is where
			# you are every time you walk to it.
			_stand_player(_spine_point(0)),
		"during": func(tick: int) -> void:
			if tick != 60:
				return
			# The claim that makes the wing worth building: walking to one room
			# must not put you in a fight with the occupants of the others.
			for i in [1, 2]:
				var bot := _duel(i)
				if bot == null:
					continue
				_expect(not _brain(bot).senses.can_see(_player),
						"%s cannot see the corridor outside room 0" % bot.name)
				_expect(_brain(bot).senses.visible_target == null,
						"%s has no target while you approach room 0" % bot.name),
		"check": func() -> void:
			_expect(_all_duel_bots_home(), "every duel bot stayed in its room"),
	},
	{
		"name": "fighting one duel bot does not pull the others in",
		"ticks": 720,
		"setup": func() -> void:
			_reset_counters()
			var bounds := ArenaBuilder.duel_bounds(1)
			var centre := bounds.get_center()
			# Inside the Regular room, past the baffle.
			_stand_player(Vector3(bounds.end.x - 3.0, 1.0, centre.z))
			var bot := _duel(1)
			if bot != null:
				_watch_shots(bot),
		"during": func(tick: int) -> void:
			_player.health.heal(100.0)
			var bot := _duel(1)
			if bot != null and is_instance_valid(bot):
				_observe(bot, tick)
			# Checked every tick, not just at the end: a bot that leaves and
			# comes back would pass an end-state check while having spent the
			# fight somewhere it should never have been.
			if not _all_duel_bots_home():
				_fired_during_reload = true,
		"check": func() -> void:
			_expect(_observed_states.has(&"bot_engage"),
					"the room's own bot fought you")
			_expect(_shots > 0, "and shot at you (%d)" % _shots)
			_expect(not _fired_during_reload,
					"no duel bot left its room at any point during the fight")
			_expect(_player_hits > 0,
					"you took fire from it (%d hits)" % _player_hits),
	},
	{
		"name": "a killed duel bot comes back in its own room",
		"ticks": 900,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(0.0, 1.0, 0.0))
			var bot := _duel(2)
			if bot == null:
				return
			var info := DamageInfo.new()
			info.amount = bot.health.max_health * 2.0
			info.source = _player
			info.victim = bot
			bot.health.apply_damage(info),
		"check": func() -> void:
			var bot := _duel(2)
			_expect(bot != null and is_instance_valid(bot), "still there")
			if bot == null:
				return
			_expect(bot.health.is_alive, "revived")
			_expect(BotDirector._inside(ArenaBuilder.duel_bounds(2),
					bot.global_position),
					"respawned inside the Veteran room, not out in the arena"),
	},
	{
		"name": "a roaming bot shoved into a duel room walks back out",
		"ticks": 1200,
		"setup": func() -> void:
			_reset_counters()
			_stand_player(Vector3(0.0, 1.0, 0.0))
			_director.bot_count = 1,
		"during": func(tick: int) -> void:
			# Dropped in once the roster has actually spawned one.
			if tick == 120 and _bot() != null:
				var bounds := ArenaBuilder.duel_bounds(0)
				var centre := bounds.get_center()
				_bot().global_position = Vector3(centre.x, 1.0, centre.z)
				_bot().velocity = Vector3.ZERO,
		"check": func() -> void:
			var bot := _bot()
			_expect(bot != null, "the roaming bot still exists")
			if bot == null:
				return
			_expect(not BotDirector._inside(ArenaBuilder.duel_bounds(0),
					bot.global_position),
					"found its way out of the duel room (now at %s)"
					% str(bot.global_position.round()))
			_expect(BotDirector._inside(ArenaBuilder.main_arena_bounds(),
					bot.global_position),
					"and back into the arena it belongs in"),
	},
	]

# ---------------------------------------------------------------------------

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % description)
		return
	print("    FAIL %s" % description)
	_failures.append("%s: %s" % [_plan[_phase]["name"], description])

func _finish() -> bool:
	print("\n=== %d checks, %d failed ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	var ok := _failures.is_empty() and _checks > 0
	if _checks == 0:
		print("bot smoke test ran no checks")
	print("bot smoke test %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
	return true
