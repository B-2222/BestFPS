extends SceneTree
## Headless behavioural check on the movement controller.
##
## Run: godot --headless --path . --script scripts/tests/movement_smoke_test.gd
## Exits non-zero on failure, so it can gate a build once CI exists.
##
## These are not unit tests of feel -- feel is not testable and must be judged
## by hand. They assert the things that *are* objective and that silently break
## when a tuning value is edited: does the player reach its top speed, does it
## stop, is the jump the height the numbers say it is, and does the stair code
## climb what it should while refusing what it should not.
##
## It drives the controller by writing InputCommands directly, which is the
## same seam bots and the network layer will use. That the test can exist at
## all is the payoff for keeping input out of the movement code.

const TOLERANCE_STOP := 0.5

var _player: PlayerController
var _config: PlayerConfig
var _plan: Array = []
var _phase := 0
var _phase_tick := 0
var _failures: PackedStringArray = PackedStringArray()
var _checks := 0
var _peak_y := 0.0
var _peak_speed := 0.0
var _saw_slide_state := false
var _airborne_ticks := 0

## Height of the bare test plane. Far enough above the arena that no blockout
## geometry can reach it.
const PLANE_Y := 500.0

func _initialize() -> void:
	var arena: Node = load("res://scenes/levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	_build_open_plane(arena)

	_player = arena.get_node("Player") as PlayerController
	# Detach the device layer; this test is the input source now.
	_player.set_input_source(null)
	_config = _player.config

	_player.movement_state_changed.connect(func(id: StringName) -> void:
		if id == &"slide":
			_saw_slide_state = true)

	_build_plan()
	print("\n=== movement smoke test (%d phases) ===\n" % _plan.size())

func _physics_process(delta: float) -> bool:
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
# Plan
# ---------------------------------------------------------------------------

func _build_plan() -> void:
	var hz := float(Engine.physics_ticks_per_second)
	var forward := func(_t: int) -> void: _player.cmd.move_axis = Vector2(0, 1)

	_plan = [
		{
			"name": "spawns and settles on the floor",
			"ticks": int(hz * 0.75),
			"check": func() -> void:
				_expect(_player.is_on_floor(), "player is grounded after settling")
				_expect_near(_player.global_position.y, 0.0, 0.05,
						"feet rest on the floor plane"),
		},
		{
			"name": "reaches walk speed",
			"ticks": int(hz * 0.5),
			"during": forward,
			"check": func() -> void:
				var speed := _player.get_horizontal_speed()
				_expect(speed >= _config.walk_speed * 0.9,
						"walk speed %.2f >= 90%% of %.2f within 0.5 s" % [speed, _config.walk_speed]),
		},
		{
			"name": "reaches sprint speed",
			"ticks": int(hz * 0.6),
			"during": func(_t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				_player.cmd.sprint_held = true,
			"check": func() -> void:
				var speed := _player.get_horizontal_speed()
				_expect(speed >= _config.sprint_speed * 0.9,
						"sprint speed %.2f >= 90%% of %.2f" % [speed, _config.sprint_speed]),
		},
		{
			"name": "stops when input is released",
			"ticks": int(hz * 0.5),
			"check": func() -> void:
				var speed := _player.get_horizontal_speed()
				_expect(speed < TOLERANCE_STOP,
						"speed %.3f decays below %.1f m/s within 0.5 s" % [speed, TOLERANCE_STOP]),
		},
		{
			"name": "jump apex matches the configured physics",
			"ticks": int(hz * 1.2),
			"setup": func() -> void:
				_place(Vector3(0, 0.2, 0), 0.0)
				_peak_y = -100.0,
			"during": func(t: int) -> void:
				if t == 2:
					_player.cmd.jump_pressed = true
					_player.cmd.jump_held = true
				_peak_y = maxf(_peak_y, _player.global_position.y),
			"check": func() -> void:
				var expected := (_config.jump_velocity * _config.jump_velocity) \
						/ (2.0 * _config.gravity)
				_expect_near(_peak_y, expected, expected * 0.15,
						"apex %.3f m is within 15%% of the predicted %.3f m" % [_peak_y, expected])
				_expect(_player.is_on_floor(), "lands again within 1.2 s"),
		},
		{
			# Peak, not final: the flight is only 3.2 m long, and a player who
			# keeps walking crosses the landing and drops off the far side.
			"name": "climbs a 0.35 m staircase (at the step limit)",
			"ticks": int(hz * 1.4),
			"setup": func() -> void:
				_place(Vector3(19.0, 0.2, -6.0), 0.0)
				_peak_y = 0.0,
			"during": func(_t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				_peak_y = maxf(_peak_y, _player.global_position.y),
			"check": func() -> void:
				_expect(_peak_y > 2.0,
						"climbed to y=%.2f (top of the flight is 2.80)" % _peak_y),
		},
		{
			# Descending is a separate failure mode from climbing: if
			# floor_snap_length drops below max_step_height the player leaves
			# the ground on every step and the descent turns into a rattle.
			"name": "walks down the same staircase without bouncing",
			"ticks": int(hz * 1.5),
			"setup": func() -> void:
				_place(Vector3(19.0, 3.0, -13.0), PI)
				_airborne_ticks = 0,
			"during": func(t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				# Skip the settle: the phase spawns slightly above the landing.
				if t > 40 and not _player.is_on_floor():
					_airborne_ticks += 1,
			"check": func() -> void:
				_expect(_player.global_position.y < 0.1,
						"reached the bottom (y=%.2f)" % _player.global_position.y)
				var total := int(Engine.physics_ticks_per_second * 1.5) - 40
				_expect(float(_airborne_ticks) / float(total) < 0.25,
						"stayed grounded for %d of %d ticks of the descent"
						% [total - _airborne_ticks, total]),
		},
		{
			# Two assertions on purpose. "Did not rise" alone would also pass if
			# the player never reached the ledge at all, which would make this
			# test permanently green and permanently worthless.
			"name": "refuses a 0.40 m ledge (above the step limit)",
			"ticks": int(hz * 2.0),
			"setup": func() -> void:
				_place(Vector3(17.0, 0.2, 4.0), PI)
				_peak_y = 0.0,
			"during": func(t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				# Ignore the first quarter second: the phase spawns the player
				# 0.2 m up so it drops onto the floor, and that drop is not a
				# climb.
				if t > 30:
					_peak_y = maxf(_peak_y, _player.global_position.y),
			"check": func() -> void:
				_expect(_player.global_position.z > 5.5,
						"actually walked up to the ledge (z=%.2f, face is at 6.10)"
						% _player.global_position.z)
				_expect(_peak_y < 0.15,
						"never rose above y=%.2f, so the 0.40 m ledge held" % _peak_y),
		},
		{
			"name": "crouching shrinks the hull",
			"ticks": int(hz * 0.5),
			"setup": func() -> void: _place(Vector3(0, 0.2, 0), 0.0),
			"during": func(_t: int) -> void: _player.cmd.crouch_held = true,
			"check": func() -> void:
				_expect(_player.is_crouched, "crouch flag is set")
				_expect_near(_player.get_current_height(), _config.crouch_height, 0.05,
						"hull height %.2f reached crouch height %.2f"
						% [_player.get_current_height(), _config.crouch_height]),
		},
		{
			"name": "stands back up in the open",
			"ticks": int(hz * 0.5),
			"check": func() -> void:
				_expect(not _player.is_crouched, "crouch released")
				_expect_near(_player.get_current_height(), _config.standing_height, 0.05,
						"hull returned to %.2f m" % _config.standing_height),
		},
		{
			"name": "sprint into crouch enters a slide and gains speed",
			"ticks": int(hz * 1.0),
			"setup": func() -> void:
				_place(Vector3(0, 0.2, 20.0), PI)
				_peak_speed = 0.0,
			"during": func(t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				_player.cmd.sprint_held = true
				# Crouch once, after sprint speed has built up.
				var trigger := int(Engine.physics_ticks_per_second * 0.6)
				if t == trigger:
					_player.cmd.crouch_pressed = true
				if t >= trigger:
					_player.cmd.crouch_held = true
					_peak_speed = maxf(_peak_speed, _player.get_horizontal_speed()),
			"check": func() -> void:
				_expect(_saw_slide_state, "entered the slide state")
				_expect(_peak_speed > _config.sprint_speed,
						"slide peaked at %.2f m/s, above sprint speed %.2f"
						% [_peak_speed, _config.sprint_speed]),
		},
		{
			# Holding jump must not be free speed. If straight-line bhop beat
			# sprinting there would be no reason ever to walk.
			"name": "auto-bhop in a straight line does not beat sprinting",
			"ticks": int(hz * 6.0),
			"setup": func() -> void:
				_place(Vector3(0.0, PLANE_Y + 0.2, 0.0), 0.0),
			"during": func(t: int) -> void:
				_player.cmd.move_axis = Vector2(0, 1)
				_player.cmd.sprint_held = true
				_player.cmd.jump_held = true
				_player.cmd.jump_pressed = (t == 30),
			"check": func() -> void:
				var speed := _player.get_horizontal_speed()
				_expect(speed > _config.walk_speed * 0.8,
						"kept moving at %.2f m/s rather than grinding to a halt" % speed)
				_expect(speed <= _config.sprint_speed + 0.5,
						"%.2f m/s stayed at or below sprint speed %.2f"
						% [speed, _config.sprint_speed]),
		},
		{
			# Strafe jumping must still be worth learning...
			"name": "strafe jumping accelerates past sprint speed",
			"ticks": int(hz * 6.0),
			"setup": func() -> void:
				_place(Vector3(0.0, PLANE_Y + 0.2, 0.0), 0.0),
			"during": func(t: int) -> void:
				# Strafe and turn together -- that pairing is the technique.
				_player.yaw -= 2.4 / hz
				_player.rotation.y = _player.yaw
				_player.cmd.move_axis = Vector2(1, 0)
				_player.cmd.jump_held = true
				_player.cmd.jump_pressed = (t == 30),
			"check": func() -> void:
				var speed := _player.get_horizontal_speed()
				_expect(speed > _config.sprint_speed * 1.2,
						"reached %.2f m/s, well past sprint speed %.2f"
						% [speed, _config.sprint_speed]),
		},
		{
			# ...but must not run away. The Quake air model has no natural
			# ceiling; measured at 23 m/s and still climbing before the cap.
			"name": "sustained strafe jumping stays under the air speed cap",
			"ticks": int(hz * 14.0),
			"setup": func() -> void:
				_place(Vector3(0.0, PLANE_Y + 0.2, 0.0), 0.0)
				_peak_speed = 0.0,
			"during": func(t: int) -> void:
				_player.yaw -= 2.4 / hz
				_player.rotation.y = _player.yaw
				_player.cmd.move_axis = Vector2(1, 0)
				_player.cmd.jump_held = true
				_player.cmd.jump_pressed = (t == 30)
				_peak_speed = maxf(_peak_speed, _player.get_horizontal_speed()),
			"check": func() -> void:
				_expect(_peak_speed <= _config.max_air_speed + 0.01,
						"peaked at %.2f m/s, held under the %.2f m/s cap"
						% [_peak_speed, _config.max_air_speed]),
		},
	]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Bunny hopping needs hundreds of metres of clear ground; the arena is 80 m
## across and its walls would silently cap any speed measurement taken inside
## it. So these phases run on their own plane instead.
func _build_open_plane(parent: Node) -> void:
	var body := StaticBody3D.new()
	body.name = "OpenTestPlane"
	body.position = Vector3(0.0, PLANE_Y - 1.0, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 2.0, 8000.0)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)

func _place(pos: Vector3, yaw: float) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = pos
	_player.yaw = yaw
	_player.rotation.y = yaw
	_player.is_crouched = false
	_player.jump_buffer = 0.0
	_player.slide_cooldown_left = 0.0
	_player.machine.transition_to(&"air")

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % description)
	else:
		print("    FAIL %s" % description)
		_failures.append("%s: %s" % [_plan[_phase]["name"], description])

func _expect_near(value: float, target: float, tolerance: float, description: String) -> void:
	_expect(absf(value - target) <= tolerance, description)

func _finish() -> bool:
	print("\n=== %d checks, %d failed ===" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	if _failures.is_empty():
		print("movement smoke test PASSED\n")
		quit(0)
	else:
		print("movement smoke test FAILED\n")
		quit(1)
	return true
