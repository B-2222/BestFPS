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

## Browser-to-browser controls, used where a download is not an option.
var _p2p_section: VBoxContainer
var _p2p_out: TextEdit
var _p2p_out_label: Label
var _p2p_copy: Button
var _p2p_in: TextEdit
var _p2p_in_label: Label
var _p2p_action: Button
var _p2p_paste: Button
## Frames left to wait for the browser to answer a clipboard read.
var _paste_wait: int = 0
var _p2p_host: Button
var _lan_section: VBoxContainer
## What we have been handed to give the other player.
var _our_blob := ""
## True on the web build, where LAN is impossible and this is the only route.
var _web := false

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
	_session.blob_ready.connect(_on_blob_ready)
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

	_lan_section.visible = not _web
	_p2p_section.visible = _web
	_refresh_p2p(hosting, joined, busy)

	_code_value.visible = hosting and not _web
	_code_hint.visible = hosting and not _web
	if hosting:
		if _session.join_code == "":
			_code_value.text = "no code"
			_code_hint.text = "Could not work out this machine's network " \
					+ "address. Tell them your IP instead."
		else:
			_code_value.text = _session.join_code
			_code_hint.text = "Read this out. They type it below on the same network."

	_host_button.visible = not _web
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
	blurb.text = "Same network, no account, no server. In the browser you swap " \
			+ "codes; on the desktop build the host just reads one out." \
			if OS.has_feature("web") else \
			"Same network only. No account, no server — the code is this " \
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

	_lan_section = VBoxContainer.new()
	_lan_section.add_theme_constant_override("separation", 8)
	column.add_child(_lan_section)

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
	_lan_section.add_child(entry_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_host_button = Button.new()
	_host_button.text = "Host a game"
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_host_button)
	_p2p_host = Button.new()
	_p2p_host.text = "Host in this browser"
	_p2p_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_p2p_host)
	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.custom_minimum_size = Vector2(96, 0)
	buttons.add_child(_leave_button)
	column.add_child(buttons)

	_build_p2p(column)

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

	_web = OS.has_feature("web")
	_p2p_host.visible = _web
	_host_button.pressed.connect(func() -> void:
		_message.text = ""
		_session.host())
	_p2p_host.pressed.connect(func() -> void:
		_message.text = ""
		_our_blob = ""
		_session.host_p2p())
	_p2p_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_our_blob)
		_message.text = "Copied. Send it to the other player however you like.")
	_p2p_action.pressed.connect(_p2p_pressed)
	_p2p_paste.pressed.connect(_paste_clipboard)
	_join_button.pressed.connect(_do_join)
	_entry.text_submitted.connect(func(_text: String) -> void: _do_join())
	_leave_button.pressed.connect(func() -> void:
		_message.text = ""
		_session.leave())

## The browser route: three copy-pastes and no server anywhere.
func _build_p2p(column: VBoxContainer) -> void:
	_p2p_section = VBoxContainer.new()
	_p2p_section.add_theme_constant_override("separation", 6)
	column.add_child(_p2p_section)

	_p2p_out_label = Label.new()
	_p2p_out_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p2p_out_label.add_theme_font_size_override("font_size", 12)
	_p2p_out_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	_p2p_section.add_child(_p2p_out_label)

	_p2p_out = TextEdit.new()
	_p2p_out.editable = false
	_p2p_out.custom_minimum_size = Vector2(0, 52)
	_p2p_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_p2p_out.add_theme_font_size_override("font_size", 10)
	_p2p_section.add_child(_p2p_out)

	_p2p_copy = Button.new()
	_p2p_copy.text = "Copy my code"
	_p2p_section.add_child(_p2p_copy)

	_p2p_in_label = Label.new()
	_p2p_in_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p2p_in_label.add_theme_font_size_override("font_size", 12)
	_p2p_in_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_p2p_section.add_child(_p2p_in_label)

	_p2p_in = TextEdit.new()
	_p2p_in.custom_minimum_size = Vector2(0, 52)
	_p2p_in.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_p2p_in.add_theme_font_size_override("font_size", 10)
	_p2p_section.add_child(_p2p_in)

	# A paste *button*, not just Ctrl+V into the box.
	#
	# Pasting is the single most important interaction in this whole flow, and
	# leaving it to the text field's own key handling makes it depend on how
	# one engine's canvas happens to route a browser paste event. A button that
	# asks the browser for the clipboard directly is one click, works the same
	# on every machine, and cannot be defeated by a key combination the canvas
	# never sees.
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_p2p_paste = Button.new()
	_p2p_paste.text = "Paste"
	_p2p_paste.custom_minimum_size = Vector2(96, 0)
	action_row.add_child(_p2p_paste)
	_p2p_action = Button.new()
	_p2p_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_p2p_action)
	_p2p_section.add_child(action_row)

func _on_blob_ready(blob: String) -> void:
	_our_blob = blob
	_p2p_out.text = blob
	_refresh()

## Three states, and the labels say which one you are in. The failure mode this
## avoids is two people both staring at a box with no idea whose turn it is.
func _refresh_p2p(hosting: bool, joined: bool, busy: bool) -> void:
	if not _web:
		return
	_p2p_host.disabled = hosting or joined or busy
	var have_blob := _our_blob != ""
	_p2p_out.visible = have_blob
	_p2p_out_label.visible = have_blob
	_p2p_copy.visible = have_blob

	if joined:
		_p2p_out_label.text = ""
		_p2p_in_label.text = "Connected."
		_p2p_in.visible = false
		_p2p_action.visible = false
		_p2p_paste.visible = false
		return
	_p2p_in.visible = true
	_p2p_action.visible = true
	_p2p_paste.visible = true

	if hosting:
		_p2p_out_label.text = "1. Send this code to the other player." if have_blob \
				else "Working out your code…"
		_p2p_in_label.text = "2. Paste the reply they send back, then Connect."
		_p2p_action.text = "Connect"
	elif busy:
		_p2p_out_label.text = "2. Send this reply back to the host." if have_blob \
				else "Working out your reply…"
		_p2p_in_label.text = "Waiting for the host to connect."
		_p2p_action.text = "Waiting…"
		_p2p_action.disabled = true
	else:
		_p2p_out_label.text = ""
		_p2p_in_label.text = "Paste the host's code here, then Join."
		_p2p_action.text = "Join"
		_p2p_action.disabled = false

## Ask the browser for the clipboard and drop it into the box.
##
## The web clipboard is asynchronous and only readable off the back of a real
## user gesture, which a button press is. The result is stashed on `window` by
## the promise and collected over the next few frames rather than plumbed
## through a callback object -- a button can afford to take a frame.
func _paste_clipboard() -> void:
	_message.text = ""
	if not OS.has_feature("web"):
		_p2p_in.text = DisplayServer.clipboard_get()
		return
	JavaScriptBridge.eval("""
		window.__bfps_clip = null;
		navigator.clipboard.readText()
			.then(function (t) { window.__bfps_clip = t; })
			.catch(function () { window.__bfps_clip = ''; });
	""", true)
	_paste_wait = 90

func _process(_delta: float) -> void:
	if _paste_wait <= 0:
		return
	_paste_wait -= 1
	var value = JavaScriptBridge.eval("window.__bfps_clip", true)
	if value == null:
		if _paste_wait == 0:
			_message.text = "The browser would not hand over the clipboard. " \
					+ "Click in the box and paste with the keyboard instead."
		return
	_paste_wait = 0
	var text := String(value)
	if text.strip_edges() == "":
		_message.text = "The clipboard is empty. Copy their code first."
		return
	_p2p_in.text = text

func _p2p_pressed() -> void:
	_message.text = ""
	var pasted := _p2p_in.text.strip_edges()
	if pasted == "":
		_message.text = "Paste their code into the box first."
		return
	if _session.link == NetSession.Link.HOSTING:
		_session.accept_answer(pasted)
	else:
		_our_blob = ""
		_session.join_p2p(pasted)

func _do_join() -> void:
	_message.text = ""
	_session.join(_entry.text)
