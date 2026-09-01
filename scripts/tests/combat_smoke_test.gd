extends SceneTree
## Headless behavioural checks for weapons.
##
## Run: godot --headless --path . --script scripts/tests/combat_smoke_test.gd
##
## Same reasoning as the movement suite: how gunplay *feels* has to be judged by
## hand, but fire rate, damage, falloff, headshot reward and time-to-kill are
## arithmetic, and they are exactly the numbers that drift silently when someone
## nudges a value in a .tres.

var _player: PlayerController
var _weapons: WeaponController
var _rifle: WeaponResource
var _plan: Array = []
var _phase := 0
var _phase_tick := 0
var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

var _shots_fired := 0
var _last_damage := 0.0
var _body_damage_near := 0.0
var _head_damage_near := 0.0
var _body_damage_far := 0.0
var _shots_to_kill := 0
var _shot_damage := 0.0
var _target_died := false

var _arena: Node

var _wired := false

func _initialize() -> void:
	_arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	_disable_bots(_arena)
	root.add_child(_arena)
	_player = _arena.get_node("Player") as PlayerController
	_player.set_input_source(null)

## Bots are switched off for the movement and combat suites.
##
## They wander, shoot, make noise and get in the way, and any of that landing in
## a firing lane turns a measurement into a coin flip -- a bot stepping through
## a trace is indistinguishable from a falloff bug, and one that kills the
## player freezes the movement phases outright.
##
## The whole node is removed rather than having its count zeroed, because
## BotDirector reads the roster back out of the GameSettings autoload on ready.
## Autoloads *do* exist under `--script`, contrary to what a couple of comments
## in this project used to claim, so a zeroed count is overwritten by whatever
## is in the developer's saved settings a moment later.
static func _disable_bots(arena: Node) -> void:
	var director: Node = arena.get_node_or_null(^"BotDirector")
	if director == null:
		return
	arena.remove_child(director)
	director.free()

## Wiring happens on the first physics tick, not in _initialize(). Nodes added
## to the tree do not run _ready() until the frame begins, so the player's
## @onready WeaponController reference is still null at initialise time.
func _wire() -> void:
	_wired = true
	_weapons = _player.weapons
	if _weapons == null:
		push_error("combat smoke test: player has no WeaponController")
		quit(1)
		return
	_rifle = _weapons.current().resource
	# fired is emitted before the traces resolve, so resetting here and summing
	# in hit_confirmed gives the total damage of one shot -- which is the only
	# meaningful number for a shotgun.
	_weapons.fired.connect(func(_w: WeaponResource) -> void:
		_shots_fired += 1
		_shot_damage = 0.0)
	_weapons.hit_confirmed.connect(func(info: DamageInfo) -> void:
		_last_damage = info.amount
		_shot_damage += info.amount)
	_build_plan()
	print("\n=== combat smoke test (%d phases) ===\n" % _plan.size())

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

# ---------------------------------------------------------------------------

func _target(distance: int) -> TargetDummy:
	return _arena.get_node("Blockout/Target%dm" % distance) as TargetDummy

## Point the view at a world position. Tests aim by geometry rather than by
## hardcoded angles, so moving a target in the arena cannot silently turn a
## body shot into a miss.
func _aim_at(point: Vector3) -> void:
	var origin: Vector3 = _player.aim_point.global_position
	var to := point - origin
	_player.yaw = atan2(-to.x, -to.z)
	_player.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	_player.recoil_offset = Vector2.ZERO
	_player.apply_view()

## Four metres from the 10 m dummy: close enough that a shotgun's pellets all
## land, so per-weapon damage is a fixed number rather than a dice roll.
func _stand_close_to_target() -> void:
	var target := _target(10)
	_player.velocity = Vector3.ZERO
	_player.global_position = target.global_position + Vector3(0.0, 0.0, 4.0)
	_player.machine.transition_to(&"grounded")
	target.health.revive()

func _stand_at_firing_line() -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(-36.0, 0.0, -32.0)
	_player.machine.transition_to(&"grounded")
	# Back to the rifle. Phases must not inherit whatever the previous one left
	# equipped: a phase that expected an automatic weapon and got the
	# semi-automatic sniper fired nothing at all and still reported a result,
	# which is worse than failing.
	_force_weapon(1)

## Equip a slot instantly, skipping the draw time. Tests are checking the
## weapon, not the animation.
func _force_weapon(slot: int) -> void:
	for i in _weapons.runtimes.size():
		if _weapons.runtimes[i].resource.slot == slot:
			_weapons.current_index = i
			break
	var rt := _weapons.current()
	rt.phase = WeaponRuntime.Phase.READY
	rt.state_ticks = 0
	rt.state_ticks_total = 0
	_player.aim_has_scope = rt.resource.has_scope
	# Announced, not just assigned. Setting current_index quietly left the view
	# model still holding the previous weapon, and the *next* real switch was
	# then ignored as a no-op because the index already matched.
	_weapons.weapon_changed.emit(rt.resource)

## Reset the weapon to a known state: full magazine, no heat, no recoil.
func _reset_weapon() -> void:
	var rt := _weapons.current()
	rt.magazine = _rifle.magazine_size
	rt.reserve = _rifle.reserve_ammo
	rt.phase = WeaponRuntime.Phase.READY
	rt.state_ticks = 0
	rt.cooldown_ticks = 0
	rt.shot_index = 0
	rt.spread = 0.0
	rt.since_last_shot = 999.0
	_player.recoil_offset = Vector2.ZERO
	_shots_fired = 0
	_last_damage = 0.0

func _body_point(target: TargetDummy) -> Vector3:
	return target.global_position + Vector3(0.0, 1.23, 0.0)

func _head_point(target: TargetDummy) -> Vector3:
	return target.global_position + Vector3(0.0, 1.70, 0.0)

func _build_plan() -> void:
	var hz := float(Engine.physics_ticks_per_second)

	_plan = [
		{
			"name": "weapon starts loaded and ready",
			"ticks": 30,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon(),
			"check": func() -> void:
				var rt := _weapons.current()
				_expect(rt != null, "a weapon is equipped")
				_expect(rt.magazine == _rifle.magazine_size,
						"magazine holds %d of %d" % [rt.magazine, _rifle.magazine_size]),
		},
		{
			# Fire rate has to come from the tick counter, not from however
			# many frames happened to elapse.
			"name": "held trigger fires at the configured rate",
			"ticks": int(hz),
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				_aim_at(_body_point(_target(10))),
			"during": func(_t: int) -> void:
				_player.cmd.fire_held = true,
			"check": func() -> void:
				var expected := _rifle.rounds_per_minute / 60.0
				_expect(absf(float(_shots_fired) - expected) <= 1.0,
						"fired %d rounds in 1 s, expected about %.0f"
						% [_shots_fired, expected])
				_expect(_weapons.current().magazine == _rifle.magazine_size - _shots_fired,
						"magazine dropped by exactly the rounds fired"),
		},
		{
			"name": "a body shot at 10 m damages the target",
			"ticks": 20,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				_target(10).health.revive()
				_aim_at(_body_point(_target(10))),
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.fire_pressed = true
					_player.cmd.fire_held = true,
			"check": func() -> void:
				_body_damage_near = _last_damage
				_expect(_last_damage > 0.0, "registered %.1f damage" % _last_damage)
				_expect(absf(_last_damage - _rifle.damage) < 0.01,
						"%.1f matches the rifle's %.1f base damage inside falloff range"
						% [_last_damage, _rifle.damage]),
		},
		{
			"name": "a headshot rewards more than a body shot",
			"ticks": 20,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				_target(10).health.revive()
				_aim_at(_head_point(_target(10))),
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.fire_pressed = true
					_player.cmd.fire_held = true,
			"check": func() -> void:
				_head_damage_near = _last_damage
				_expect(_head_damage_near > _body_damage_near,
						"headshot %.1f beats body %.1f" % [_head_damage_near, _body_damage_near])
				var ratio := _head_damage_near / maxf(_body_damage_near, 0.001)
				_expect(absf(ratio - _rifle.headshot_multiplier) < 0.05,
						"ratio %.2f matches the configured %.2f"
						% [ratio, _rifle.headshot_multiplier]),
		},
		{
			"name": "damage falls off with distance",
			"ticks": 20,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				_target(45).health.revive()
				_aim_at(_body_point(_target(45))),
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.fire_pressed = true
					_player.cmd.fire_held = true,
			"check": func() -> void:
				_body_damage_far = _last_damage
				_expect(_body_damage_far > 0.0, "hit the 45 m target")
				_expect(_body_damage_far < _body_damage_near,
						"%.1f at 45 m is less than %.1f at 10 m"
						% [_body_damage_far, _body_damage_near])
				var floor_damage := _rifle.damage * _rifle.falloff_min_multiplier
				_expect(_body_damage_far >= floor_damage - 0.01,
						"%.1f never drops below the %.1f falloff floor"
						% [_body_damage_far, floor_damage]),
		},
		{
			"name": "time to kill is the number of shots we intend",
			"ticks": int(hz * 2.0),
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				var target := _target(10)
				target.health.revive()
				_target_died = false
				_shots_to_kill = 0
				target.health.died.connect(func(_i: DamageInfo) -> void:
					if not _target_died:
						_target_died = true
						_shots_to_kill = _shots_fired, CONNECT_ONE_SHOT)
				_aim_at(_body_point(target)),
			"during": func(_t: int) -> void:
				if not _target_died:
					_player.cmd.fire_held = true,
			"check": func() -> void:
				var expected := ceili(100.0 / _rifle.damage)
				_expect(_target_died, "killed the 100 hp target")
				_expect(_shots_to_kill == expected,
						"%d body shots to kill, matching ceil(100 / %.0f)"
						% [_shots_to_kill, _rifle.damage])
				var ttk := float(_shots_to_kill - 1) * _rifle.seconds_per_shot()
				print("        -> body TTK %.2f s, headshot damage %.1f"
						% [ttk, _head_damage_near]),
		},
		{
			"name": "reload refills the magazine from reserve",
			"ticks": int(hz * 3.0),
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				var rt := _weapons.current()
				rt.magazine = 4,
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.reload_pressed = true,
			"check": func() -> void:
				var rt := _weapons.current()
				_expect(rt.magazine == _rifle.magazine_size,
						"magazine back to %d" % rt.magazine)
				_expect(rt.reserve == _rifle.reserve_ammo - (_rifle.magazine_size - 4),
						"reserve fell by exactly the rounds loaded (%d)" % rt.reserve)
				_expect(rt.phase == WeaponRuntime.Phase.READY, "weapon is ready again"),
		},
		{
			# Not a feel test: this is the property Milestone 5 depends on. If
			# spread is not reproducible from the tick, the server and the
			# client disagree about where every bullet went.
			"name": "spread is reproducible from the command tick",
			"ticks": 10,
			"check": func() -> void:
				var forward := Vector3.FORWARD
				var spread := deg_to_rad(3.0)
				var a := Ballistics.apply_spread(forward, spread, Ballistics.make_rng(1234, 7))
				var b := Ballistics.apply_spread(forward, spread, Ballistics.make_rng(1234, 7))
				var c := Ballistics.apply_spread(forward, spread, Ballistics.make_rng(1235, 7))
				_expect(a.is_equal_approx(b),
						"same tick and salt give an identical pellet direction")
				_expect(not a.is_equal_approx(c),
						"a different tick gives a different direction"),
		},
		{
			# The reported bug: tracers drew from the eye, so while strafing the
			# streak visibly came out of the player's face. Shots are still
			# *traced* from the eye -- that is what the crosshair promises --
			# but they must be *drawn* from somewhere else.
			"name": "shots are drawn from the barrel, not the eye",
			"ticks": 10,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon(),
			"check": func() -> void:
				var muzzle: Vector3 = _player.get_muzzle_position()
				var eye: Vector3 = _player.aim_point.global_position
				_expect(muzzle.distance_to(eye) > 0.15,
						"muzzle is %.2f m from the eye" % muzzle.distance_to(eye))
				var flash: Node = _player.view_model.get_node_or_null(^"Muzzle/MuzzleFlash")
				_expect(flash != null, "the weapon has a muzzle flash to fire"),
		},
		{
			"name": "hitting world geometry leaves a bullet hole",
			"ticks": 30,
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				# Straight down at the floor -- the case that showed nothing.
				_aim_at(_player.global_position + Vector3(0.0, 0.0, -3.0)),
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.fire_pressed = true
					_player.cmd.fire_held = true,
			"check": func() -> void:
				var fx: Node = _player.weapons.get_node_or_null(^"CombatFx")
				_expect(fx != null, "the effects host exists")
				var holes := 0
				if fx != null:
					for child in fx.get_children():
						if child is MeshInstance3D and (child as MeshInstance3D).mesh is QuadMesh:
							holes += 1
				_expect(holes > 0, "%d bullet hole(s) left on the floor" % holes),
		},
		{
			# The sniper used to "aim" by parking its receiver in front of the
			# camera. Sighting an optic has to hide the weapon and hand the
			# screen to the scope instead.
			"name": "the sniper sights through an optic, not past the gun",
			"ticks": int(hz * 1.6),
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon(),
			"during": func(t: int) -> void:
				if t == 1:
					_player.cmd.weapon_slot = 3
				elif t > int(hz * 0.8):
					_player.cmd.aim_held = true,
			"check": func() -> void:
				var weapon := _weapons.current().resource
				_expect(weapon.id == &"sniper", "sniper is equipped")
				_expect(weapon.has_scope, "the sniper declares an optic")
				_expect(_player.aim_blend > 0.95,
					"fully sighted (blend %.2f)" % _player.aim_blend)
				_expect(not _player.view_model.visible,
					"the weapon model is out of the way while scoped"),
		},
		{
			# Silence is the failure mode a synthesised bank fails into: a bad
			# envelope produces a perfectly valid, empty stream and nothing
			# anywhere complains about it.
			"name": "every sound generates audible audio",
			"ticks": 10,
			"check": func() -> void:
				var names: Array[StringName] = [
					&"shot_rifle", &"shot_shotgun", &"shot_sniper", &"shot_pistol",
					&"mag_out", &"mag_in", &"charge", &"switch",
					&"footstep", &"land", &"jump", &"hit", &"hit_head", &"kill",
					&"impact",
				]
				var silent: Array[String] = []
				var lengths := {}
				for sound_name in names:
					var stream := SoundBank.get_sound(sound_name)
					var loud := false
					if stream != null:
						lengths[stream.data.size()] = true
						for i in range(0, stream.data.size() - 1, 64):
							if absi(stream.data.decode_s16(i)) > 1200:
								loud = true
								break
					if not loud:
						silent.append(String(sound_name))
				_expect(silent.is_empty(),
					"all %d sounds carry signal%s" % [names.size(),
					"" if silent.is_empty() else " except " + ", ".join(silent)])
				# Distinct lengths prove the four gunshots are not one sound
				# handed out four times.
				_expect(lengths.size() >= 8,
					"%d distinct sound lengths, so they are not clones"
					% lengths.size()),
		},
		{
			# The trackpad ceiling, as an assertion rather than a good
			# intention. Sustained climb is the per-shot kick times the fire
			# rate; past about 3 deg/s a trackpad cannot drag the view back
			# down, which is the complaint that got the rifle halved.
			"name": "no weapon out-recoils a trackpad",
			"ticks": 10,
			"check": func() -> void:
				for runtime in _weapons.runtimes:
					var weapon: WeaponResource = runtime.resource
					var total := 0.0
					for kick in weapon.recoil_pattern:
						total += kick.y
					var average := total / maxf(float(weapon.recoil_pattern.size()), 1.0)
					var climb := average * (weapon.rounds_per_minute / 60.0)
					_expect(climb < 3.0, "%s climbs %.2f deg/s under sustained fire"
							% [weapon.display_name, climb]),
		},
		{
			"name": "recoil moves the view and then recovers",
			"ticks": int(hz * 2.0),
			"setup": func() -> void:
				_stand_at_firing_line()
				_reset_weapon()
				_aim_at(_body_point(_target(20))),
			"during": func(t: int) -> void:
				# Fire for the first half second, then release and let it settle.
				if t < int(Engine.physics_ticks_per_second * 0.5):
					_player.cmd.fire_held = true
					if t == 8:
						_expect(_player.recoil_offset.y > 0.0,
								"view kicked up by %.2f deg after the first shots"
								% rad_to_deg(_player.recoil_offset.y)),
			"check": func() -> void:
				_expect(_player.recoil_offset.length() < deg_to_rad(0.2),
						"recoil recovered to %.3f deg"
						% rad_to_deg(_player.recoil_offset.length())),
		},
	]

	# One equip-and-fire phase per weapon, generated rather than written out
	# four times: every weapon must switch in, shoot, and do the damage its
	# resource claims. The intended shots-to-kill sits next to each so a tuning
	# change that quietly halves a weapon's role fails here instead of in a
	# playtest three weeks later.
	var intended := {
		&"rifle": 5, &"shotgun": 1, &"sniper": 2, &"pistol": 6,
	}
	for runtime in _weapons.runtimes:
		var weapon: WeaponResource = runtime.resource
		var expected_shots: int = intended.get(weapon.id, 0)
		_plan.append({
			"name": "%s equips, fires, and hits for what it claims" % weapon.display_name,
			"ticks": int(hz * (weapon.equip_seconds + 1.2)),
			"setup": func() -> void:
				_stand_close_to_target()
				_reset_weapon()
				_shot_damage = 0.0,
			"during": func(t: int) -> void:
				# Ask for the slot on tick 1, then wait out the equip time.
				if t == 1:
					_player.cmd.weapon_slot = weapon.slot
				elif t == int(hz * (weapon.equip_seconds + 0.35)):
					_reset_weapon()
					_aim_at(_body_point(_target(10)))
					_player.cmd.fire_pressed = true
					_player.cmd.fire_held = true,
			"check": func() -> void:
				var current := _weapons.current().resource
				_expect(current.id == weapon.id,
						"%s is equipped" % weapon.display_name)
				# The view model must have actually swapped shape, not just the
				# stats. Barrel lengths differ, so the muzzle offset does too.
				var muzzle_local: Vector3 = _player.view_model.to_local(
						_player.get_muzzle_position())
				var expected: Vector3 = ViewModel.SHAPES[weapon.view_shape]["muzzle"]
				_expect(muzzle_local.distance_to(expected) < 0.01,
						"draws the %s model (muzzle at z=%.3f)"
						% [weapon.view_shape, muzzle_local.z])
				_expect(_shot_damage > 0.0,
						"one shot dealt %.1f damage" % _shot_damage)
				var shots := ceili(100.0 / maxf(_shot_damage, 0.001))
				_expect(shots == expected_shots,
						"%d shot(s) to kill 100 hp, as intended" % shots),
		})

# ---------------------------------------------------------------------------

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % description)
	else:
		print("    FAIL %s" % description)
		_failures.append("%s: %s" % [_plan[_phase]["name"], description])

func _finish() -> bool:
	print("\n=== %d checks, %d failed ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	# A suite that ran no checks is broken, not passing. Reporting green here
	# would hide exactly the kind of setup failure that silences everything.
	var ok := _failures.is_empty() and _checks > 0
	if _checks == 0:
		print("  FAILED: no checks ran -- the suite failed to set itself up")
	print("combat smoke test %s\n" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
	return true
