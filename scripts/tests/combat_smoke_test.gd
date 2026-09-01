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
var _target_died := false

var _arena: Node

var _wired := false

func _initialize() -> void:
	_arena = load("res://scenes/levels/test_arena.tscn").instantiate()
	root.add_child(_arena)
	_player = _arena.get_node("Player") as PlayerController
	_player.set_input_source(null)

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
	_weapons.fired.connect(func(_w: WeaponResource) -> void: _shots_fired += 1)
	_weapons.hit_confirmed.connect(func(info: DamageInfo) -> void: _last_damage = info.amount)
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

func _stand_at_firing_line() -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(-36.0, 0.0, -32.0)
	_player.machine.transition_to(&"grounded")

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
