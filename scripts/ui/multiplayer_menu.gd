class_name MultiplayerMenu
extends CanvasLayer
## Host a game, or join one with a code. Opened with F5.
##
## Same shape as [SettingsMenu]: PROCESS_MODE_ALWAYS over a paused tree, so the
## player's input node stops receiving events the moment this appears and the
## two cannot fight over the same key.
##
## The code is the loudest thing on screen when hosting, because the entire
## flow is one person reading ten characters to another. Everything else here
## is secondary to that being easy to read out.

const CODE_FONT_SIZE := 40

var _root: Control
var _status: Label
var _code_value: Label
var _code_hint: Label
var _entry: LineEdit
var _message: Label
var _players: VBoxContainer
var _host_button: Button
var _join_button: Button
var _leave_button: Button

var _session: NetSession

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"multiplayer_menu")
	_session = get_node_or_null(^"/root/Net") as NetSession
	_build()
	_root.visible = false
	if _session == null:
		return
	_session.lobby_changed.connect(_refresh)
	_session.link_changed.connect(func(_link: NetSession.Link) -> void: _refresh())
	_session.failed.connect(_on_failed)
	_refresh()

func is_open() -> bool:
	return _root != null and _root.visible

func open() -> void:
	if _session == null:
		return
	_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_message.text = ""
	_refresh()
	_entry.grab_focus()

func close() -> void:
	_root.visible = false
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"multiplayer_menu"):
		close()
		get_viewport().set_input_as_handled()

func _on_failed(reason: String) -> void:
	# Recorded, never forced on screen. Opening this panel pauses the tree, and
	# a message that pauses the game the instant a packet goes astray is worse
	# than the problem it is reporting -- it froze the whole session in the
	# headless play test, which is exactly what it would do to a player
	# mid-fight. The message is waiting when they next open the panel.
	_message.text = reason

func _refresh() -> void:
	if _session == null:
		return
	var hosting := _session.link == NetSession.Link.HOSTING
	var joined := _session.link == NetSession.Link.CONNECTED
	var busy := _session.link == NetSession.Link.JOINING

	match _session.link:
		NetSession.Link.HOSTING:
			_status.text = "HOSTING  ·  %d in the lobby" % _session.roster.size()
		NetSession.Link.JOINING:
			_status.text = "CONNECTING…"
		NetSession.Link.CONNECTED:
			_status.text = "CONNECTED  ·  %d in the lobby" % _session.roster.size()
		_:
			_status.text = "NOT CONNECTED"

	_code_value.visible = hosting
	_code_hint.visible = hosting
	if hosting:
		if _session.join_code == "":
			_code_value.text = "no code"
			_code_hint.text = "Could not work out this machine's network " \
					+ "address. Tell them your IP instead."
		else:
			_code_value.text = _session.join_code
			_code_hint.text = "Read this out. They type it below on the same network."

	_host_button.disabled = hosting or joined or busy
	_join_button.disabled = hosting or joined or busy
	_leave_button.disabled = _session.link == NetSession.Link.OFFLINE

	for child in _players.get_children():
		_players.remove_child(child)
		child.queue_free()
	for peer_id in _session.ordered_peers():
		var row := Label.new()
		var mine: bool = multiplayer != null and peer_id == multiplayer.get_unique_id()
		row.text = "%s%s%s" % [_session.display_name(peer_id),
				"  (host)" if peer_id == NetSession.HOST_ID else "",
				"  — you" if mine else ""]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color",
				Color(1.0, 0.82, 0.35) if mine else Color(1, 1, 1, 0.8))
		_players.add_child(row)

# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(22)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.12)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	column.add_child(title)

	var blurb := Label.new()
	blurb.text = "Same network only. No account, no server — the code is this " \
			+ "machine's address."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(blurb)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	column.add_child(_status)
	column.add_child(HSeparator.new())

	_code_value = Label.new()
	_code_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_value.add_theme_font_size_override("font_size", CODE_FONT_SIZE)
	_code_value.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	column.add_child(_code_value)

	_code_hint = Label.new()
	_code_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code_hint.add_theme_font_size_override("font_size", 12)
	_code_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(_code_hint)

	var entry_row := HBoxContainer.new()
	entry_row.add_theme_constant_override("separation", 8)
	_entry = LineEdit.new()
	_entry.placeholder_text = "join code"
	_entry.max_length = 16
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.add_theme_font_size_override("font_size", 18)
	entry_row.add_child(_entry)
	_join_button = Button.new()
	_join_button.text = "Join"
	_join_button.custom_minimum_size = Vector2(96, 0)
	entry_row.add_child(_join_button)
	column.add_child(entry_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_host_button = Button.new()
	_host_button.text = "Host a game"
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_host_button)
	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.custom_minimum_size = Vector2(96, 0)
	buttons.add_child(_leave_button)
	column.add_child(buttons)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 13)
	_message.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	column.add_child(_message)

	column.add_child(HSeparator.new())
	var players_title := Label.new()
	players_title.text = "IN THE LOBBY"
	players_title.add_theme_font_size_override("font_size", 12)
	players_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	column.add_child(players_title)

	_players = VBoxContainer.new()
	_players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_players)

	var footer := Label.new()
	footer.text = "F5 or Esc to close"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	column.add_child(footer)

	_host_button.pressed.connect(func() -> void:
		_message.text = ""
		_session.host())
	_join_button.pressed.connect(_do_join)
	_entry.text_submitted.connect(func(_text: String) -> void: _do_join())
	_leave_button.pressed.connect(func() -> void:
		_message.text = ""
		_session.leave())

func _do_join() -> void:
	_message.text = ""
	_session.join(_entry.text)
