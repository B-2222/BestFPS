class_name CombatHud
extends CanvasLayer
## Crosshair, hit markers and ammo. Game UI, not developer furniture -- unlike
## [DebugHud] this stays on screen when F3 is toggled off.

const HITMARKER_SECONDS := 0.28
const KILL_MARKER_SECONDS := 0.5

var player: PlayerController
var weapons: WeaponController

var _crosshair: Crosshair
var _ammo: Label
var _weapon_name: Label
var _reload: Label

func _ready() -> void:
	layer = 5
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	if player != null:
		weapons = player.weapons
	_build()
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
	_crosshair.spread_pixels = _spread_to_pixels(weapons.current_spread_degrees())
	_crosshair.advance(delta)

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

## Four ticks whose gap is the real spread cone, plus a hit marker overlay.
class Crosshair:
	extends Control

	var spread_pixels: float = 6.0

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
