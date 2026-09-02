extends Node
## Autoload. Owns everything the player can change and expects to still be
## there next time: key bindings and mouse sensitivity.
##
## Bindings are stored as a compact description ({"type": "key", "code": 87})
## rather than as serialised InputEvent objects. The file stays readable, and
## it cannot break when a future Godot changes how it writes objects.
##
## Defaults are snapshotted from the InputMap at startup rather than duplicated
## in a table here, so project.godot stays the single source of truth for what
## the game ships with.

signal binding_changed(action: StringName)
signal sensitivity_changed(scale: float)
signal volume_changed(linear: float)
## The bot roster changed. [BotDirector] listens rather than polling, so the
## setting takes effect the moment the slider moves.
signal match_settings_changed()

const SETTINGS_PATH := "user://settings.cfg"

## Rebindable actions, in the order the menu lists them.
const REBINDABLE: Array = [
	[&"move_forward", "Move forward"],
	[&"move_back", "Move back"],
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"jump", "Jump"],
	[&"crouch", "Crouch / slide"],
	[&"sprint", "Sprint"],
	[&"fire", "Fire"],
	[&"aim", "Aim down sights"],
	[&"reload", "Reload"],
	[&"weapon_1", "Weapon 1"],
	[&"weapon_2", "Weapon 2"],
	[&"weapon_3", "Weapon 3"],
	[&"weapon_4", "Weapon 4"],
	[&"respawn", "Respawn"],
	[&"debug_toggle", "Toggle stats"],
]

## Multiplier on the tuned sensitivity in PlayerConfig, so the design default
## stays put and the player's preference layers on top of it.
var mouse_sensitivity_scale: float = 1.0
## Master output, 0..1 linear.
var master_volume: float = 0.7

## How many bots the match should contain, and how good they are (0 easy,
## 1 normal, 2 hard).
##
## Kept here rather than on the level so it survives a scene reload and, in
## Milestone 5, so the lobby has one place to read a player's preferred match
## setup from before handing it to the host.
## Defaults to Recruit rather than Regular on purpose. Three Regular bots
## delete a stationary player in about a second and a half, which is a fine
## thing for them to be capable of and a terrible first thirty seconds. It is
## one click away in the settings menu, and the tier is named in the menu so
## turning it up is an obvious thing to do.
var bot_count: int = 3
var bot_difficulty: int = 0

## Keep one bot of each tier in the duel wing's sealed rooms. On by default:
## the rooms are a labelled instrument, and an instrument with nothing in it
## is a corridor.
var duel_bots: bool = true

var _defaults: Dictionary = {}

func _ready() -> void:
	for entry in REBINDABLE:
		var action: StringName = entry[0]
		if InputMap.has_action(action):
			_defaults[action] = InputMap.action_get_events(action).duplicate()
	_apply_volume()
	load_settings()

# --- bindings --------------------------------------------------------------

func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	binding_changed.emit(action)
	save_settings()

func reset_action(action: StringName) -> void:
	if not _defaults.has(action):
		return
	InputMap.action_erase_events(action)
	for event in _defaults[action]:
		InputMap.action_add_event(action, event)
	binding_changed.emit(action)

func reset_all() -> void:
	for action in _defaults:
		reset_action(action)
	mouse_sensitivity_scale = 1.0
	sensitivity_changed.emit(mouse_sensitivity_scale)
	set_master_volume(0.7)
	bot_count = 3
	bot_difficulty = 0
	duel_bots = true
	match_settings_changed.emit()

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	volume_changed.emit(master_volume)
	save_settings()

func _apply_volume() -> void:
	# linear_to_db(0) is -inf, which Godot accepts but which reads badly in a
	# debugger; mute explicitly instead.
	if master_volume <= 0.001:
		AudioServer.set_bus_mute(0, true)
		return
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))

func set_bot_count(value: int) -> void:
	bot_count = clampi(value, 0, 12)
	match_settings_changed.emit()
	save_settings()

func set_bot_difficulty(value: int) -> void:
	bot_difficulty = clampi(value, 0, 2)
	match_settings_changed.emit()
	save_settings()

func set_duel_bots(enabled: bool) -> void:
	duel_bots = enabled
	match_settings_changed.emit()
	save_settings()

func set_sensitivity_scale(value: float) -> void:
	mouse_sensitivity_scale = clampf(value, 0.1, 5.0)
	sensitivity_changed.emit(mouse_sensitivity_scale)
	save_settings()

## Human-readable label for whatever is currently bound.
func describe(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "Unbound"
	return describe_event(events[0])

static func describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		var text := OS.get_keycode_string(code)
		return text if text != "" else "Key %d" % code
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left click"
			MOUSE_BUTTON_RIGHT: return "Right click"
			MOUSE_BUTTON_MIDDLE: return "Middle click"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			_: return "Mouse %d" % (event as InputEventMouseButton).button_index
	# Strip Godot's " (Physical)" suffix, which is noise in a settings menu.
	return event.as_text().replace(" (Physical)", "")

## Bindings we can store. Anything else (a gamepad axis, say) is rejected at
## the menu rather than silently saved and lost on the next launch.
static func is_bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false

# --- persistence -----------------------------------------------------------

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "sensitivity_scale", mouse_sensitivity_scale)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("match", "bot_count", bot_count)
	config.set_value("match", "bot_difficulty", bot_difficulty)
	config.set_value("match", "duel_bots", duel_bots)
	for entry in REBINDABLE:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			continue
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			continue
		config.set_value("bindings", String(action), _encode(events[0]))
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save settings (%d). Bindings will not persist." % error)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return  # No settings yet; project defaults stand.
	mouse_sensitivity_scale = float(config.get_value("input", "sensitivity_scale", 1.0))
	master_volume = float(config.get_value("audio", "master_volume", 0.7))
	bot_count = clampi(int(config.get_value("match", "bot_count", 3)), 0, 12)
	bot_difficulty = clampi(int(config.get_value("match", "bot_difficulty", 0)), 0, 2)
	duel_bots = bool(config.get_value("match", "duel_bots", true))
	_apply_volume()
	for entry in REBINDABLE:
		var action: StringName = entry[0]
		var encoded = config.get_value("bindings", String(action), null)
		if encoded == null or not InputMap.has_action(action):
			continue
		var event := _decode(encoded)
		if event == null:
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)
	sensitivity_changed.emit(mouse_sensitivity_scale)

func _encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"type": "key", "code": key.physical_keycode if key.physical_keycode != 0 else key.keycode}
	if event is InputEventMouseButton:
		return {"type": "mouse", "code": (event as InputEventMouseButton).button_index}
	return {}

func _decode(data) -> InputEvent:
	if not (data is Dictionary) or not data.has("type"):
		return null
	match data["type"]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data["code"])
			return key
		"mouse":
			var button := InputEventMouseButton.new()
			button.button_index = int(data["code"])
			return button
	return null
