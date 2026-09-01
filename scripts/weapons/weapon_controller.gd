class_name WeaponController
extends Node
## Owns the loadout and turns [InputCommand] into shots.
##
## Reads only the command, never the [Input] singleton -- the same seam the
## movement uses, for the same reasons (bots in M3, replay in M5). All timing is
## in physics ticks rather than seconds, so a replayed command produces an
## identical result; see docs/networking-decision.md.

signal weapon_changed(weapon: WeaponResource)
signal ammo_changed(magazine: int, reserve: int)
signal fired(weapon: WeaponResource)
signal hit_confirmed(info: DamageInfo)
signal killed(info: DamageInfo)
signal reload_started(seconds: float)
signal reload_finished()

## Fallback loadout when the scene does not specify one. A list of paths rather
## than a single weapon so the remaining Milestone 2 weapons are a one-line
## addition here plus a .tres, with no code change.
const DEFAULT_LOADOUT: Array[String] = [
	"res://assets/config/weapons/rifle.tres",
	"res://assets/config/weapons/shotgun.tres",
	"res://assets/config/weapons/sniper.tres",
	"res://assets/config/weapons/pistol.tres",
]

@export var loadout: Array[WeaponResource] = []
@export var player_path: NodePath = ^".."

var runtimes: Array[WeaponRuntime] = []
var current_index: int = 0
var is_aiming: bool = false

var _player: PlayerController
var _fx: CombatFx
var _hz: float = 120.0

func _ready() -> void:
	_player = get_node(player_path) as PlayerController
	_hz = float(Engine.physics_ticks_per_second)

	if loadout.is_empty():
		for path in DEFAULT_LOADOUT:
			var weapon := load(path) as WeaponResource
			if weapon != null:
				loadout.append(weapon)
	for weapon in loadout:
		runtimes.append(WeaponRuntime.new(weapon))

	_ensure_fx()
	if not runtimes.is_empty():
		weapon_changed.emit(current().resource)
		ammo_changed.emit(current().magazine, current().reserve)

## Effects must not ride along with the player -- parented normally, a tracer
## would follow you down the corridor instead of hanging in the air where it
## was fired.
##
## Solved with top_level rather than by reparenting to the level: adding to the
## level during _ready() fails outright ("parent node is busy setting up
## children"), and deferring it leaves a window where a shot fired on the first
## frame has nowhere to draw. top_level makes the node ignore the player's
## transform while still being an ordinary child, so it is valid immediately.
func _ensure_fx() -> void:
	_fx = CombatFx.new()
	_fx.name = "CombatFx"
	_fx.top_level = true
	add_child(_fx)

func current() -> WeaponRuntime:
	if runtimes.is_empty():
		return null
	return runtimes[clampi(current_index, 0, runtimes.size() - 1)]

func seconds_to_ticks(seconds: float) -> int:
	return maxi(int(round(seconds * _hz)), 0)

## Driven by [PlayerController] once per physics tick.
func tick(cmd: InputCommand, delta: float) -> void:
	var rt := current()
	if rt == null:
		return

	rt.since_last_shot += delta
	if rt.cooldown_ticks > 0:
		rt.cooldown_ticks -= 1
	_advance_state(rt)

	_handle_switch(cmd)
	rt = current()

	is_aiming = cmd.aim_held and rt.phase == WeaponRuntime.Phase.READY
	_handle_reload(cmd, rt)
	_handle_fire(cmd, rt)
	_recover(rt, delta)
	_push_player_modifiers(rt)

func _advance_state(rt: WeaponRuntime) -> void:
	if rt.state_ticks <= 0:
		return
	rt.state_ticks -= 1
	if rt.state_ticks > 0:
		return
	if rt.phase == WeaponRuntime.Phase.RELOADING:
		var wanted: int = rt.resource.magazine_size - rt.magazine
		var moved: int = mini(wanted, rt.reserve)
		rt.magazine += moved
		rt.reserve -= moved
		rt.shot_index = 0
		rt.spread = rt.resource.spread_min
		reload_finished.emit()
		ammo_changed.emit(rt.magazine, rt.reserve)
	rt.phase = WeaponRuntime.Phase.READY

func _handle_switch(cmd: InputCommand) -> void:
	if cmd.weapon_slot < 0:
		return
	for i in runtimes.size():
		if runtimes[i].resource.slot != cmd.weapon_slot or i == current_index:
			continue
		current_index = i
		var rt := runtimes[i]
		# Switching cancels a reload rather than queueing it. Weapon swap is a
		# legitimate way to escape a long reload, and players expect it.
		rt.phase = WeaponRuntime.Phase.EQUIPPING
		rt.state_ticks = seconds_to_ticks(rt.resource.equip_seconds)
		rt.state_ticks_total = rt.state_ticks
		rt.shot_index = 0
		rt.spread = rt.resource.spread_min
		weapon_changed.emit(rt.resource)
		ammo_changed.emit(rt.magazine, rt.reserve)
		return

func _handle_reload(cmd: InputCommand, rt: WeaponRuntime) -> void:
	var wants_reload := cmd.reload_pressed
	# Auto-reload on a dry trigger pull. Without it the failure mode is
	# clicking an empty gun at someone, which is never what the player meant.
	if not wants_reload and rt.needs_reload() and (cmd.fire_pressed or cmd.fire_held):
		wants_reload = true
	if not wants_reload or not rt.can_reload():
		return
	rt.phase = WeaponRuntime.Phase.RELOADING
	rt.state_ticks = seconds_to_ticks(rt.resource.reload_seconds)
	rt.state_ticks_total = rt.state_ticks
	reload_started.emit(rt.resource.reload_seconds)

func _handle_fire(cmd: InputCommand, rt: WeaponRuntime) -> void:
	var wants := cmd.fire_held if rt.resource.automatic else cmd.fire_pressed
	if not wants or not rt.can_fire():
		return
	_fire(cmd, rt)

func _fire(cmd: InputCommand, rt: WeaponRuntime) -> void:
	var res := rt.resource
	rt.magazine -= 1
	rt.cooldown_ticks = maxi(seconds_to_ticks(res.seconds_per_shot()), 1)
	rt.since_last_shot = 0.0

	# Announced before the traces resolve, so that anything reacting to a hit
	# or a kill already counts the shot that caused it. Emitting afterwards
	# made "shots fired" lag "target died" by one, which is the kind of
	# off-by-one that quietly corrupts a TTK readout.
	fired.emit(res)
	ammo_changed.emit(rt.magazine, rt.reserve)

	var origin: Vector3 = _player.aim_point.global_position
	var forward: Vector3 = -_player.aim_point.global_transform.basis.z
	var spread_rad := deg_to_rad(current_spread_degrees())
	var space := _player.get_world_3d().direct_space_state
	# Traced from the eye, drawn from the barrel. Keeping these apart is the
	# whole point: the eye is what the crosshair promises and what the server
	# will validate, while a tracer starting at the camera visibly emerges from
	# the player's face when they strafe.
	var muzzle: Vector3 = _player.get_muzzle_position()

	for pellet in res.pellets:
		_trace_pellet(cmd, rt, space, origin, forward, spread_rad, pellet, muzzle)

	# Recoil is applied *after* tracing, deliberately. The shot goes where the
	# player was aiming when they pulled the trigger; the kick moves the next
	# one. Kicking first would mean the bullet never goes where the crosshair
	# was, which reads as the game stealing shots.
	_player.apply_recoil(res.recoil_for_shot(rt.shot_index))

	rt.shot_index += 1
	rt.spread = minf(rt.spread + res.spread_per_shot, res.spread_max)

func _trace_pellet(cmd: InputCommand, rt: WeaponRuntime,
		space: PhysicsDirectSpaceState3D, origin: Vector3, forward: Vector3,
		spread_rad: float, pellet: int, muzzle: Vector3) -> void:
	var res := rt.resource
	# Salt keeps pellets of one shot independent while staying reproducible.
	var rng := Ballistics.make_rng(cmd.tick, rt.shot_index * 64 + pellet)
	var direction := Ballistics.apply_spread(forward, spread_rad, rng)
	var destination := origin + direction * res.max_range

	var query := PhysicsRayQueryParameters3D.create(
			origin, destination, Ballistics.TRACE_MASK, [_player.get_rid()])
	query.collide_with_areas = true   # hitboxes are Areas
	query.collide_with_bodies = true  # world geometry is not
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_fx.tracer(muzzle, destination)
		return

	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	_fx.tracer(muzzle, point)

	if not (collider is Hitbox):
		_fx.impact(point, normal, false)
		_fx.bullet_hole(point, normal)
		return

	var hitbox := collider as Hitbox
	var info := DamageInfo.new()
	info.amount = Ballistics.resolve_damage(res, hitbox, origin.distance_to(point))
	info.source = _player
	info.weapon_id = res.id
	info.hitbox_id = hitbox.hitbox_id
	info.is_headshot = hitbox.is_headshot()
	info.position = point
	info.normal = normal
	info.distance = origin.distance_to(point)
	info.tick = cmd.tick

	_fx.impact(point, normal, true)
	_fx.damage_number(point, info.amount, info.is_headshot)
	hit_confirmed.emit(info)

	if hitbox.health == null:
		return
	var was_alive := hitbox.health.is_alive
	hitbox.health.apply_damage(info)
	if was_alive and not hitbox.health.is_alive:
		killed.emit(info)

## Spread actually used for the next shot, after movement and aim modifiers.
## The HUD reads this to size the crosshair, so what you see is what fires.
func current_spread_degrees() -> float:
	var rt := current()
	if rt == null:
		return 0.0
	var res := rt.resource
	var speed_fraction := clampf(
			_player.get_horizontal_speed() / maxf(_player.config.sprint_speed, 0.001),
			0.0, 1.0)
	var spread := rt.spread + res.spread_moving * speed_fraction
	if is_aiming:
		spread *= res.spread_aim_multiplier
	return spread

func _recover(rt: WeaponRuntime, delta: float) -> void:
	var res := rt.resource
	rt.spread = maxf(rt.spread - res.spread_recovery * delta, res.spread_min)
	if rt.since_last_shot >= res.recoil_recovery_delay:
		_player.recover_recoil(deg_to_rad(res.recoil_recovery * delta))
	# Restart the pattern only once the player has genuinely stopped shooting,
	# so a brief pause mid-burst does not hand back a fresh first shot.
	if rt.since_last_shot > res.recoil_recovery_delay + 0.35:
		rt.shot_index = 0

func _push_player_modifiers(rt: WeaponRuntime) -> void:
	var res := rt.resource
	var multiplier := res.move_speed_multiplier
	if is_aiming:
		multiplier = minf(multiplier, res.aim_move_multiplier)
	_player.speed_multiplier = multiplier
	_player.is_aiming = is_aiming
	_player.aim_fov_reduction = res.aim_fov_reduction
	_player.aim_has_scope = res.has_scope
