class_name AudioDirector
extends Node
## Turns gameplay signals into sound.
##
## Everything it needs was already being emitted -- `fired`, `landed`,
## `jumped`, `hit_confirmed`, `reload_started`, `weapon_changed` -- which is
## the payoff for having the controllers announce what they do instead of
## reaching into each other. Adding audio touched no gameplay code.
##
## Voices come from a pool. A single AudioStreamPlayer restarts on play(), so
## one player firing at 600 rpm would cut its own 0.22 s tail ten times a
## second and sound like a stapler.

const VOICES := 10
const WORLD_VOICES := 6
## Metres between footfalls at a walk.
const STRIDE := 2.15

var _player: PlayerController
var _weapons: WeaponController

var _voices: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _world_voices: Array[AudioStreamPlayer3D] = []
var _world_index: int = 0

var _step_distance: float = 0.0
var _reload_stage: int = 0

func _ready() -> void:
	_player = _find_controller()
	if _player == null:
		set_process(false)
		return

	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for i in WORLD_VOICES:
		var voice := AudioStreamPlayer3D.new()
		# top_level so an impact stays where it happened instead of following
		# the player who caused it.
		voice.top_level = true
		voice.unit_size = 12.0
		voice.max_distance = 90.0
		add_child(voice)
		_world_voices.append(voice)

	_player.jumped.connect(func() -> void: play(&"jump", -14.0))
	_player.landed.connect(_on_landed)

func _find_controller() -> PlayerController:
	var node := get_parent()
	while node != null:
		if node is PlayerController:
			return node
		node = node.get_parent()
	return null

## Same lazy resolution as the view model: children ready before parents, so
## the player's weapon controller is not available in _ready().
func _ensure_weapons() -> void:
	if _weapons != null or _player.weapons == null:
		return
	_weapons = _player.weapons
	_weapons.fired.connect(_on_fired)
	_weapons.weapon_changed.connect(func(_w: WeaponResource) -> void:
		play(&"switch", -12.0))
	_weapons.hit_confirmed.connect(_on_hit)
	_weapons.killed.connect(func(_i: DamageInfo) -> void: play(&"kill", -6.0))
	_weapons.reload_started.connect(func(_s: float) -> void: _reload_stage = 0)

func _process(delta: float) -> void:
	_ensure_weapons()
	_update_footsteps(delta)
	_update_reload()

# ---------------------------------------------------------------------------

func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var voice := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	voice.stream = SoundBank.get_sound(sound)
	voice.volume_db = volume_db
	# A little pitch variation stops repeated sounds turning into a machine.
	voice.pitch_scale = pitch * randf_range(0.96, 1.04)
	voice.play()

func play_at(sound: StringName, position: Vector3, volume_db: float = 0.0) -> void:
	var voice := _world_voices[_world_index]
	_world_index = (_world_index + 1) % _world_voices.size()
	voice.stream = SoundBank.get_sound(sound)
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(0.92, 1.08)
	voice.global_position = position
	voice.play()

func _on_fired(weapon: WeaponResource) -> void:
	play(StringName("shot_%s" % weapon.id), -5.0)

func _on_hit(info: DamageInfo) -> void:
	play(&"hit_head" if info.is_headshot else &"hit", -12.0)
	play_at(&"impact", info.position, -8.0)

func _on_landed(impact_speed: float) -> void:
	# Scaled by how hard the landing was, so a hop and a long drop are not the
	# same event. Below walking pace it is not worth hearing at all.
	if impact_speed < 2.0:
		return
	var weight := clampf(impact_speed / 18.0, 0.0, 1.0)
	play(&"land", lerpf(-22.0, -6.0, weight), lerpf(1.15, 0.85, weight))

## Driven by distance travelled rather than a timer, so footfalls stay in step
## with the legs at any speed -- the same reason the camera bob is.
func _update_footsteps(delta: float) -> void:
	if not _player.is_on_floor():
		_step_distance = 0.0
		return
	var speed := _player.get_horizontal_speed()
	if speed < 0.6:
		return
	_step_distance += speed * delta
	if _step_distance < STRIDE:
		return
	_step_distance = 0.0
	var loudness := clampf(speed / maxf(_player.config.sprint_speed, 0.001), 0.0, 1.0)
	# Crouching is quiet, which is the point of crouching.
	var quiet := -9.0 if _player.is_crouched else 0.0
	play(&"footstep", lerpf(-26.0, -16.0, loudness) + quiet)

## Reload is a sequence, not one noise. Driven off the weapon's own progress so
## it stays in step with each weapon's reload time, and stops cleanly if the
## reload is cancelled by a weapon switch.
func _update_reload() -> void:
	if _weapons == null:
		return
	var runtime := _weapons.current()
	if runtime == null or runtime.phase != WeaponRuntime.Phase.RELOADING:
		_reload_stage = 0
		return
	var progress := runtime.phase_progress()
	if _reload_stage == 0 and progress > 0.10:
		_reload_stage = 1
		play(&"mag_out", -13.0)
	elif _reload_stage == 1 and progress > 0.58:
		_reload_stage = 2
		play(&"mag_in", -12.0)
	elif _reload_stage == 2 and progress > 0.86:
		_reload_stage = 3
		play(&"charge", -14.0)
