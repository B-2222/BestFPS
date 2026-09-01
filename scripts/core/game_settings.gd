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

var _defaults: Dictionary = {}

func _ready() -> void:
	for entry in REBINDABLE:
		var action: StringName = entry[0]
		if InputMap.has_action(action):
			_defaults[action] = InputMap.action_get_events(action).duplicate()
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
