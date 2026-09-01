class_name CombatHud
extends CanvasLayer
## Crosshair, hit markers and ammo. Game UI, not developer furniture -- unlike
## [DebugHud] this stays on screen when F3 is toggled off.

const HITMARKER_SECONDS := 0.28
const KILL_MARKER_SECONDS := 0.5
## How long a kill-feed line stays up.
const FEED_SECONDS := 5.0
const FEED_MAX_LINES := 5

var player: PlayerController
var weapons: WeaponController
var director: BotDirector

var _crosshair: Crosshair
var _scope: ScopeOverlay
var _ammo: Label
var _weapon_name: Label
var _reload: Label
var _health: HealthBar
var _damage: DamageOverlay
var _feed: VBoxContainer
var _score: Label
var _status: Label

var _player_frags: int = 0
var _bot_frags: int = 0

func _ready() -> void:
	layer = 5
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	if player != null:
		weapons = player.weapons
	director = get_tree().get_first_node_in_group(&"bot_director") as BotDirector
	_build()
	if player != null and player.health != null:
		player.health.damaged.connect(_on_player_damaged)
		player.health.healed.connect(_on_player_healed)
		player.health.died.connect(_on_player_died)
		player.health.revived.connect(_on_player_revived)
		_health.fraction = player.health.fraction()
	if director != null:
		director.fragged.connect(_on_fragged)
		_refresh_score()
	if weapons != null:
		weapons.ammo_changed.connect(_on_ammo_changed)
		weapons.hit_confirmed.connect(_on_hit)
		weapons.killed.connect(_on_kill)
		weapons.reload_started.connect(_on_reload_started)
		weapons.reload_finished.connect(_on_reload_finished)
		weapons.weapon_changed.connect(_on_weapon_changed)
		var rt := weapons.current()
		if rt != null:
			_on_ammo_changed(rt.magazine, rt.reserve)
			_on_weapon_changed(rt.resource)

func _process(delta: float) -> void:
	if weapons == null or _crosshair == null:
		return
	var scoped := player != null and player.aim_has_scope
	# The optic replaces the crosshair rather than sitting behind it. Two
	# aiming references on screen at once is just clutter.
	_scope.blend = player.aim_blend if scoped else 0.0
	_scope.visible = _scope.blend > 0.01
	_crosshair.scoped_out = _scope.blend > 0.55

	_crosshair.spread_pixels = _spread_to_pixels(weapons.current_spread_degrees())
	_crosshair.advance(delta)
	if _scope.visible:
		_scope.queue_redraw()

	if player.health != null:
		_health.advance(delta, player.health.fraction())
	_damage.advance(delta, player)
	_expire_feed(delta)

## Convert the spread cone to the radius it actually covers on screen, so the
## crosshair is a truthful picture of where a bullet can land rather than a
## decorative widget that grows a bit when you move.
func _spread_to_pixels(spread_degrees: float) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 6.0
	var viewport_height := float(get_viewport().get_visible_rect().size.y)
	var half_fov := deg_to_rad(camera.fov) * 0.5
	var pixels_per_radian := (viewport_height * 0.5) / maxf(tan(half_fov), 0.0001)
	return tan(deg_to_rad(spread_degrees)) * pixels_per_radian

func _on_ammo_changed(magazine: int, reserve: int) -> void:
	# Plain text: Label does not parse BBCode, and feeding it markup prints the
	# tags on screen rather than colouring anything.
	_ammo.text = "%d / %d" % [magazine, reserve]
	_ammo.modulate = Color(1.0, 0.45, 0.4) if magazine == 0 else Color(1, 1, 1)

func _on_weapon_changed(weapon: WeaponResource) -> void:
	_weapon_name.text = "%d  %s" % [weapon.slot, weapon.display_name.to_upper()]

func _on_hit(info: DamageInfo) -> void:
	_crosshair.flash(HITMARKER_SECONDS,
			Color(1.0, 0.82, 0.35) if info.is_headshot else Color(1, 1, 1))

func _on_kill(_info: DamageInfo) -> void:
	_crosshair.flash(KILL_MARKER_SECONDS, Color(1.0, 0.35, 0.32))

func _on_reload_started(seconds: float) -> void:
	_reload.text = "RELOADING"
	_reload.visible = true
	var tween := create_tween()
	tween.tween_interval(seconds)

func _on_reload_finished() -> void:
	_reload.visible = false

func _build() -> void:
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_scope = ScopeOverlay.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	add_child(_scope)

	_ammo = Label.new()
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo.offset_left = -220
	_ammo.offset_top = -76
	_ammo.offset_right = -32
	_ammo.offset_bottom = -32
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo.add_theme_font_size_override("font_size", 34)
	_ammo.text = "--"
	add_child(_ammo)

	_weapon_name = Label.new()
	_weapon_name.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_name.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_name.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapon_name.offset_left = -240
	_weapon_name.offset_top = -102
	_weapon_name.offset_right = -32
	_weapon_name.offset_bottom = -76
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_name.add_theme_font_size_override("font_size", 15)
	_weapon_name.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_weapon_name.text = ""
	add_child(_weapon_name)

	_reload = Label.new()
	_reload.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_reload.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reload.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_reload.offset_top = -120
	_reload.offset_bottom = -96
	_reload.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reload.add_theme_font_size_override("font_size", 18)
	_reload.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_reload.visible = false
	add_child(_reload)

	_health = HealthBar.new()
	_health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_health.offset_left = 32
	_health.offset_top = -76
	_health.offset_right = 292
	_health.offset_bottom = -32
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health)

	# Above the crosshair and below everything else: it is a full-screen tint
	# and a ring of direction markers, and both read as part of the world
	# rather than as part of the interface.
	_damage = DamageOverlay.new()
	_damage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage)
	move_child(_damage, 0)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = -420
	_feed.offset_top = 24
	_feed.offset_right = -32
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	_score = Label.new()
	_score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score.offset_top = 18
	_score.offset_bottom = 44
	_score.offset_left = -200
	_score.offset_right = 200
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 17)
	_score.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_score.text = ""
	add_child(_score)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BOTH
	_status.offset_left = -220
	_status.offset_right = 220
	_status.offset_top = -80
	_status.offset_bottom = -46
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 26)
	_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	_status.visible = false
	add_child(_status)

# --- player status ----------------------------------------------------------

func _on_player_damaged(info: DamageInfo, remaining: float) -> void:
	_health.punch(remaining / maxf(player.health.max_health, 0.001))
	# Where it came from matters more than how much it was: without a direction
	# the first thing you learn about a bot is that it already killed you.
	if info.source != null and info.source is Node3D:
		_damage.mark((info.source as Node3D).global_position)

func _on_player_healed(_amount: float, remaining: float) -> void:
	_health.fraction = remaining / maxf(player.health.max_health, 0.001)

func _on_player_died(info: DamageInfo) -> void:
	_status.text = "ELIMINATED"
	_status.visible = true
	_damage.blackout = 1.0
	if director == null:
		_push_feed("%s eliminated YOU" % _name_of(info.source), Color(1.0, 0.42, 0.38))

func _on_player_revived() -> void:
	_status.visible = false
	_damage.blackout = 0.0
	_health.fraction = 1.0
	_health.ghost = 1.0

func _on_fragged(attacker: Node, victim: Node, headshot: bool) -> void:
	var player_did_it := attacker == player
	var player_died := victim == player
	if player_did_it and not player_died:
		_player_frags += 1
	elif player_died:
		_bot_frags += 1
	_refresh_score()

	var colour := Color(0.72, 0.90, 1.0)
	if player_died:
		colour = Color(1.0, 0.42, 0.38)
	elif player_did_it:
		colour = Color(1.0, 0.82, 0.35)
	var mark := "  [HEAD]" if headshot else ""
	_push_feed("%s  >  %s%s" % [_name_of(attacker), _name_of(victim), mark], colour)

func _refresh_score() -> void:
	_score.text = "YOU %d      BOTS %d" % [_player_frags, _bot_frags]

func _name_of(node: Node) -> String:
	if node == null:
		return "THE WORLD"
	if node == player:
		return "YOU"
	var brain := node.get_node_or_null(^"BotBrain") as BotBrain
	if brain != null and brain.profile != null:
		return "%s (%s)" % [node.name.to_upper(), brain.profile.display_name]
	return node.name.to_upper()

func _push_feed(text: String, colour: Color) -> void:
	var line := Label.new()
	line.text = text
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_color_override("font_color", colour)
	line.set_meta(&"expires", FEED_SECONDS)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_MAX_LINES:
		_drop_line(_feed.get_child(0) as Label)

func _expire_feed(delta: float) -> void:
	for child in _feed.get_children():
		var line := child as Label
		var left: float = float(line.get_meta(&"expires")) - delta
		line.set_meta(&"expires", left)
		if left <= 0.0:
			_drop_line(line)
		elif left < 1.0:
			line.modulate.a = left

## Removed before freeing, not after: queue_free() does not take effect until
## the end of the frame, so a line that is only queued still counts toward the
## line limit and still gets its timer decremented.
func _drop_line(line: Label) -> void:
	if line == null:
		return
	_feed.remove_child(line)
	line.queue_free()

## Four ticks whose gap is the real spread cone, plus a hit marker overlay.
class Crosshair:
	extends Control

	var spread_pixels: float = 6.0
	## Suppressed while an optic owns the screen.
	var scoped_out: bool = false

	var _flash_time: float = 0.0
	var _flash_total: float = 0.0
	var _flash_color: Color = Color(1, 1, 1)

	func _ready() -> void:
		resized.connect(queue_redraw)

	func flash(seconds: float, color: Color) -> void:
		_flash_time = seconds
		_flash_total = seconds
		_flash_color = color

	func advance(delta: float) -> void:
		if _flash_time > 0.0:
			_flash_time = maxf(_flash_time - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		if scoped_out:
			return
		var centre := size * 0.5
		# Floor at 4 px: a pinpoint crosshair is unreadable, and the gap should
		# never imply more accuracy than the weapon has.
		var gap := maxf(spread_pixels, 4.0)
		var length := 7.0
		var thickness := 2.0
		var color := Color(1, 1, 1, 0.9)
		draw_line(centre + Vector2(0, -gap), centre + Vector2(0, -gap - length), color, thickness)
		draw_line(centre + Vector2(0, gap), centre + Vector2(0, gap + length), color, thickness)
		draw_line(centre + Vector2(-gap, 0), centre + Vector2(-gap - length, 0), color, thickness)
		draw_line(centre + Vector2(gap, 0), centre + Vector2(gap + length, 0), color, thickness)
		draw_rect(Rect2(centre - Vector2(1, 1), Vector2(2, 2)), color, true)

		if _flash_time <= 0.0:
			return
		# Diagonal ticks, so a hit reads instantly as different from the
		# crosshair itself rather than as the crosshair changing size.
		var alpha := _flash_time / maxf(_flash_total, 0.001)
		var marker := Color(_flash_color.r, _flash_color.g, _flash_color.b, alpha)
		var inner := 5.0
		var outer := 11.0
		for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(centre + corner * inner, centre + corner * outer, marker, 2.0)

## The sniper's sight picture: everything outside a circle blacked out, with a
## reticle inside.
##
## The blackout is one very thick arc rather than a masked texture. Control has
## no "draw everything except this circle" primitive, and a ring whose width
## reaches past the screen corners is exactly that, in one call, at any
## resolution.
class ScopeOverlay:
	extends Control

	## 0 hip, 1 fully sighted. Drives both opacity and the circle's size.
	var blend: float = 0.0

	const RING_SEGMENTS := 128

	func _draw() -> void:
		if blend <= 0.01:
			return
		var centre := size * 0.5
		# Fade in over the back half of the raise, so the optic arrives with
		# the zoom rather than before it.
		var alpha := clampf((blend - 0.45) / 0.45, 0.0, 1.0)
		if alpha <= 0.0:
			return

		var radius := minf(size.x, size.y) * 0.42 * (0.90 + 0.10 * blend)
		# Thick enough to reach past the corners at any aspect ratio.
		var reach := size.length() * 0.5
		var thickness := reach - radius + 24.0
		draw_arc(centre, radius + thickness * 0.5, 0.0, TAU, RING_SEGMENTS,
				Color(0, 0, 0, alpha), thickness, true)
		draw_arc(centre, radius, 0.0, TAU, RING_SEGMENTS,
				Color(0.06, 0.07, 0.09, alpha), 3.0, true)

		var ink := Color(0.04, 0.05, 0.06, alpha)
		var gap := radius * 0.055
		var arm := radius * 0.92
		draw_line(centre + Vector2(-arm, 0), centre + Vector2(-gap, 0), ink, 1.5, true)
		draw_line(centre + Vector2(gap, 0), centre + Vector2(arm, 0), ink, 1.5, true)
		draw_line(centre + Vector2(0, -arm), centre + Vector2(0, -gap), ink, 1.5, true)
		draw_line(centre + Vector2(0, gap), centre + Vector2(0, arm), ink, 1.5, true)

		# Holdover dots below the centre, the usual way a scope marks drop.
		for i in range(1, 5):
			var y := radius * 0.16 * float(i)
			var width := radius * (0.030 if i % 2 == 0 else 0.018)
			draw_line(centre + Vector2(-width, y), centre + Vector2(width, y), ink, 1.5, true)

		draw_circle(centre, 1.6, ink)

## Health, with a delayed ghost behind the bar.
##
## The ghost is the point. A bar that just shrinks tells you your health; a bar
## that shrinks instantly and then has a red remainder draining behind it tells
## you *how much of it just happened*, which is the difference between knowing
## you are hurt and knowing you are being shot at right now.
class HealthBar:
	extends Control

	## 0..1, follows the real value immediately.
	var fraction: float = 1.0
	## Trails behind, drains toward [member fraction].
	var ghost: float = 1.0
	## Seconds of hold before the ghost starts draining.
	var _hold: float = 0.0

	const GHOST_HOLD := 0.35
	const GHOST_DRAIN := 0.85

	func _ready() -> void:
		set_process(false)   # driven by the HUD so it shares one delta

	func punch(new_fraction: float) -> void:
		if new_fraction < fraction:
			_hold = GHOST_HOLD
		else:
			ghost = maxf(ghost, new_fraction)
		fraction = new_fraction
		queue_redraw()

	func advance(delta: float, actual: float) -> void:
		# Regeneration moves the bar without a signal per tick, so the real
		# value is re-read here rather than only on damage.
		if not is_equal_approx(actual, fraction):
			fraction = actual
			queue_redraw()
		if ghost <= fraction:
			ghost = fraction
			return
		_hold = maxf(_hold - delta, 0.0)
		if _hold > 0.0:
			return
		ghost = maxf(ghost - GHOST_DRAIN * delta, fraction)
		queue_redraw()

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		draw_rect(box, Color(0.04, 0.05, 0.07, 0.62))
		var bar := Rect2(Vector2(2, 2), Vector2(maxf(size.x - 4, 0), maxf(size.y - 4, 0)))
		if ghost > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ghost, bar.size.y)),
					Color(0.85, 0.22, 0.20, 0.65))
		# Green while healthy, amber under half, red under a quarter: the
		# colour has to change before the length does, because you read colour
		# from the corner of your eye and length only if you look at it.
		var colour := Color(0.45, 0.85, 0.55)
		if fraction < 0.25:
			colour = Color(1.0, 0.36, 0.32)
		elif fraction < 0.5:
			colour = Color(1.0, 0.75, 0.30)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), colour)
		draw_rect(box, Color(1, 1, 1, 0.16), false, 1.0)

		var font := ThemeDB.fallback_font
		var text := "%d" % roundi(fraction * 100.0)
		draw_string(font, Vector2(8.0, size.y * 0.5 + 7.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.05, 0.06, 0.08, 0.9))

## Screen tint plus directional hit markers.
class DamageOverlay:
	extends Control

	## Held at 1 while dead.
	var blackout: float = 0.0

	const MARKER_SECONDS := 1.6
	## Distance from screen centre, as a fraction of the shorter screen edge.
	const MARKER_RADIUS := 0.16
	## Steps in the edge falloff. Three is enough to stop it reading as a
	## hard-edged rectangle and few enough to stay free.
	const BAND_STEPS := 3

	var _hurt: float = 0.0
	var _low: float = 0.0
	## Each entry is [world position, seconds left].
	var _marks: Array = []
	var _dirty: bool = true

	func _ready() -> void:
		set_process(false)   # driven by the HUD so it shares one delta

	func mark(source: Vector3) -> void:
		_hurt = 1.0
		_marks.append([source, MARKER_SECONDS])
		_dirty = true

	func advance(delta: float, player: PlayerController) -> void:
		var was_showing := _hurt > 0.0 or _low > 0.0 or not _marks.is_empty()
		_hurt = maxf(_hurt - delta * 2.2, 0.0)
		# The edge tint tracks health rather than only pulsing on impact, so
		# "nearly dead" is a state you can see at rest and not just a thing
		# that flashes at the moment it stops being useful to know.
		var health_fraction := 1.0
		if player != null and player.health != null:
			health_fraction = player.health.fraction()
		var low := clampf((0.45 - health_fraction) / 0.45, 0.0, 1.0)
		if not is_equal_approx(low, _low):
			_low = low
			_dirty = true

		var kept: Array = []
		for entry in _marks:
			var left: float = float(entry[1]) - delta
			if left > 0.0:
				kept.append([entry[0], left])
		if kept.size() != _marks.size():
			_dirty = true
		_marks = kept

		var showing := _hurt > 0.0 or _low > 0.0 or not _marks.is_empty()
		# Markers rotate with the camera, so anything on screen has to redraw
		# every frame whether or not its own values changed.
		if showing or blackout > 0.0 or was_showing or _dirty:
			_dirty = false
			queue_redraw()

	func _draw() -> void:
		var intensity := maxf(_hurt * 0.55, _low * 0.42)
		if intensity > 0.001:
			# Drawn as four edge bands rather than a full-screen fill: a red
			# sheet across the middle of the screen hides the thing that is
			# shooting you, which makes the feedback actively harmful.
			var thickness := minf(size.x, size.y) * 0.22
			var tint := Color(0.75, 0.06, 0.05, intensity)
			for edge in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT]:
				_band(edge, thickness, tint)
		if blackout > 0.001:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.55 * blackout))
		_draw_marks(size * 0.5)

	## One screen edge, faded inward. [param edge] is the inward normal, so
	## [constant Vector2.DOWN] is the top of the screen. Stepped rather than
	## smooth because draw_rect has no gradient and a real one would need a
	## texture built from an image.
	func _band(edge: Vector2, thickness: float, tint: Color) -> void:
		for step in BAND_STEPS:
			var t := float(step) / float(BAND_STEPS)
			var near := thickness * t
			var depth := thickness / float(BAND_STEPS)
			var faded := Color(tint.r, tint.g, tint.b, tint.a * (1.0 - t))
			if edge == Vector2.DOWN:
				draw_rect(Rect2(0.0, near, size.x, depth), faded)
			elif edge == Vector2.UP:
				draw_rect(Rect2(0.0, size.y - near - depth, size.x, depth), faded)
			elif edge == Vector2.RIGHT:
				draw_rect(Rect2(near, 0.0, depth, size.y), faded)
			else:
				draw_rect(Rect2(size.x - near - depth, 0.0, depth, size.y), faded)

	## An arc pointing at whatever hit you.
	func _draw_marks(centre: Vector2) -> void:
		if _marks.is_empty():
			return
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var basis := camera.global_transform.basis
		var eye := camera.global_position
		var radius := minf(size.x, size.y) * MARKER_RADIUS
		for entry in _marks:
			var offset: Vector3 = (entry[0] as Vector3) - eye
			# Into the camera's own frame, then flattened. What is wanted is
			# the bearing on the screen plane, so a shooter directly behind
			# reads as behind rather than as a point at infinity.
			var local := basis.inverse() * offset
			# Camera space is +X right, -Z forward; screen space is +X right,
			# +Y *down*. So (x, z) maps straight across: forward (0,-1) is up,
			# behind (0,+1) is down, and no extra rotation is needed.
			var bearing := Vector2(local.x, local.z)
			if bearing.length_squared() < 0.0001:
				continue
			var angle := bearing.normalized().angle()
			var alpha: float = clampf(float(entry[1]) / MARKER_SECONDS, 0.0, 1.0)
			draw_arc(centre, radius, angle - 0.35, angle + 0.35, 16,
					Color(1.0, 0.3, 0.26, alpha), 4.0, true)
