extends Node3D
## Local 2–4 player game. Rules have no dependency on the presentation.
const Lore := preload("res://Factions.gd")
const Briefing := preload("res://src/UI/overlays/FactionBriefing.gd")
const Overlay := preload("res://src/UI/components/MoveOverlay.gd")
const SIDEBAR_WIDTH := 288.0
const Rules := preload("res://ParquesRules.gd")
const DiceScene := preload("res://DiceThrow.tscn")
const ExtractionProgressScene := preload("res://src/UI/components/ExtractionProgress.tscn")
const SidebarHUDScene := preload("res://src/UI/hud/SidebarHUD.tscn")
const LobbyOverlayScene := preload("res://src/UI/overlays/LobbyOverlay.tscn")
const DiceOverlayScene := preload("res://src/UI/overlays/DiceOverlay.tscn")
const SoundSettingsOverlayScene := preload("res://src/UI/overlays/SoundSettingsOverlay.tscn")
const VictoryOverlayScene := preload("res://src/UI/overlays/VictoryOverlay.tscn")
const OptionsMenuScene := preload("res://src/UI/menus/OptionsMenu.tscn")
const CyberTheme := preload("res://src/UI/theme/cyber_theme.tres")
const DEFAULT_COLORS := [0, 2, 1, 3]
var game := Rules.new()
const Guide := preload("res://FieldGuide.gd")
var guide := Guide.new()
@export var remember_guidance := true
var effects: Node3D
var audio: Node
var guide_dismiss: Button
var _guide_event := ""
var _guide_event_until := 0.0
var _details_open := false
var settings: MenuButton
var guide_beacon: Control
var command_dock: PanelContainer
var comms_reveal: Node
var _comms_id := ""
var _reaction_text := ""
var _reaction_until := 0.0
var _reaction_team := 0
var sound_overlay: Control
var options_overlay: OptionsMenu
@export var remember_audio_settings := true
var board: Node3D
var camera: Camera3D
var ui: Control
var setup_overlay: Control
var dice_overlay: Control
var victory_overlay: Control
var dice_stage: Node3D
var dice_viewport: SubViewport
var dice_caption: Label
var dice_result: Label
var roster: VBoxContainer
var turn_title: Label
var status: Label
var dice_labels: Array[Label] = []
var actions: Container
var choices: VBoxContainer
var pawn_buttons: GridContainer
var move_overlay: Control
var cell_info: Label
var phase_badge: Label
var focus_button: Button
var _view_player := -1
var _glow_material: StandardMaterial3D
var _selected_glow: StandardMaterial3D
var roll_button: Button
var lobby_button: Button
var setup_error: Label
var player_count: OptionButton
var fast_dice: CheckBox
var name_inputs: Array[LineEdit] = []
var color_inputs: Array[OptionButton] = []
var player_rows: Array[HBoxContainer] = []
var highlights: Node3D
var _selected := -1
var _busy := false
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _log: Array[Dictionary] = []
var _generated_lobby_names: Array[String] = []
var _dice_player_name := ""
var _dice_opening := false
var _displayed_dice: Array[int] = []
var _reaction_event := ""
var history_label: Label
var _victory_shown := false
var faction_briefing: Control
var faction_card: PanelContainer
var faction_portrait: Control
var faction_heading: Label
var faction_speaker: Label
var faction_message: Label
var lobby_portrait: Control
var lobby_faction_name: Label
var lobby_character: Label
var lobby_description: Label
var _host_faction := -1
var _host_player_name := ""
var _opening_player_name := ""
var _host_opens_match := true
var _last_game_phase := "lobby"
## Future clients can set this to their local player's faction (color ID).
## -1 uses the opening winner as the shared screen's narrator.
@export_range(-1, 3) var local_faction_id: int = -1

func _ready() -> void:
	board = get_node("Board")
	camera = get_node("Camera3D")
	_rng.randomize()
	highlights = Node3D.new()
	highlights.name = "MoveHighlights"
	board.add_child(highlights)
	guide.remember = remember_guidance
	guide.restore()
	effects = preload("res://ArenaEffects.gd").new()
	board.add_child(effects)
	audio = preload("res://ArenaAudio.gd").new()
	audio.remember_preferences = remember_audio_settings
	add_child(audio)
	comms_reveal = preload("res://src/UI/components/DialogueReveal.gd").new()
	add_child(comms_reveal)
	comms_reveal.tick.connect(func(): audio.play("text", maxi(0, _host_faction)))
	_build_backdrop()
	_build_ui()
	game.changed.connect(_on_game_changed)
	
	if MatchConfig.has_pending_match():
		var entries: Array[Dictionary] = MatchConfig.consume_match_players()
		if MatchConfig.pending_fast_dice:
			fast_dice.button_pressed = true
		start_match_with_entries(entries)
	else:
		show_lobby()

func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(command_dock) and is_instance_valid(setup_overlay) and is_instance_valid(dice_overlay):
		command_dock.visible = not setup_overlay.visible and not dice_overlay.visible and not _briefing_open() and not _options_menu_open() and game.phase != "game_over"
	if is_instance_valid(faction_card):
		_refresh_guidance()
		faction_portrait.speaking = faction_card.is_visible_in_tree() and comms_reveal.revealing
	for portrait in get_tree().get_nodes_in_group("AnimatedPortraits"):
		portrait.motion_enabled = audio.portrait_motion
	if is_instance_valid(roll_button) and not roll_button.disabled and guide.active in ["opening", "jail", "roll"]:
		roll_button.modulate = Color.WHITE.lerp(Color("8ce5eb"), .25 + sin(_clock * 3) * .2)
	elif is_instance_valid(roll_button):
		roll_button.modulate = Color.WHITE
	if is_instance_valid(move_overlay):
		move_overlay.bounds = get_play_rect()
		_update_cell_info()
	if _glow_material:
		_glow_material.emission_energy_multiplier = 0.8 + sin(_clock * 4.5) * 0.25
	for child in highlights.get_children():
		if child is MeshInstance3D:
			var pulse := 1.0 + sin(_clock * 4.5) * 0.07
			child.scale = Vector3(pulse, 1, pulse)

func get_play_rect() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Rect2(18, 18, maxf(100, viewport_size.x - SIDEBAR_WIDTH - 52), maxf(100, viewport_size.y - 62))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameUI"
	add_child(layer)
	ui = Control.new()
	ui.name = "Interface"
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = CyberTheme
	move_overlay = Overlay.new()
	move_overlay.name = "BoardTargets"
	ui.add_child(move_overlay)
	move_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_overlay.camera = camera
	move_overlay.bounds = get_play_rect()
	move_overlay.picked.connect(_pin_picked)

	var side := SidebarHUDScene.instantiate() as PanelContainer
	command_dock = side
	side.name = "Sidebar"
	side.add_theme_stylebox_override("panel", _style(Color(.018, .035, .05, .9), Color(.16, .29, .34, .5)))
	ui.add_child(side)

	faction_card = side.find_child("FactionContact", true, false) as PanelContainer
	faction_portrait = side.find_child("FactionPortrait", true, false) as Control
	faction_heading = side.find_child("FactionHeading", true, false) as Label
	faction_speaker = side.find_child("FactionSpeaker", true, false) as Label
	faction_message = side.find_child("FactionMessage", true, false) as Label
	faction_message.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			comms_reveal.complete()
	)
	guide_dismiss = side.find_child("GuideDismiss", true, false) as Button
	guide_dismiss.pressed.connect(_dismiss_guidance)
	faction_card.hide()

	roster = side.find_child("Roster", true, false) as VBoxContainer
	turn_title = side.find_child("TurnTitle", true, false) as Label
	phase_badge = side.find_child("PhaseBadge", true, false) as Label

	dice_labels.clear()
	dice_labels.append(side.find_child("Die0", true, false) as Label)
	dice_labels.append(side.find_child("Die1", true, false) as Label)

	status = side.find_child("Status", true, false) as Label
	actions = side.find_child("Actions", true, false) as Container
	roll_button = side.find_child("RollDice", true, false) as Button
	roll_button.pressed.connect(_roll_clicked)
	lobby_button = side.find_child("LobbyButton", true, false) as Button
	lobby_button.pressed.connect(show_lobby)

	pawn_buttons = side.find_child("PawnButtons", true, false) as GridContainer
	choices = side.find_child("Choices", true, false) as VBoxContainer

	var overview_btn := side.find_child("OverviewButton", true, false) as Button
	overview_btn.pressed.connect(func(): camera.overview())
	focus_button = side.find_child("FocusButton", true, false) as Button
	focus_button.pressed.connect(_focus_selected)
	var view_toggle_btn := side.find_child("ViewToggleButton", true, false) as Button
	view_toggle_btn.pressed.connect(func(): camera.toggle_angle())

	settings = side.find_child("Settings", true, false) as MenuButton
	var menu := settings.get_popup()
	menu.add_item(tr("MENU_PROLOGUE"), 0)
	menu.add_item(tr("MENU_RESTART_GUIDANCE"), 1)
	menu.add_check_item(tr("MENU_MOVE_LIST"), 2)
	menu.add_check_item(tr("MENU_COORDINATES"), 3)
	menu.add_item(tr("MENU_CAMERA_CONTROLS"), 4)
	menu.add_check_item(tr("MENU_MUTE_SOUND"), 5)
	menu.add_item(tr("MENU_AUDIO_SETTINGS"), 6)
	menu.add_item(tr("MENU_GENERAL_OPTIONS"), 7)
	menu.set_item_checked(menu.get_item_index(5), not audio.enabled)
	menu.id_pressed.connect(_menu_action)

	var history_panel := side.find_child("HistoryPanel", true, false) as PanelContainer
	history_label = side.find_child("HistoryLabel", true, false) as Label
	history_panel.hide()

	cell_info = _label(ui, "", 14, Color("e0f5fc"))
	cell_info.anchor_top = 1
	cell_info.anchor_bottom = 1
	cell_info.offset_left = 22
	cell_info.offset_top = -32
	cell_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_material = _pawn_glow(Color("79ffff"))
	_selected_glow = _pawn_glow(Color("fff3a6"))
	guide_beacon = preload("res://src/UI/components/GuideBeacon.gd").new()
	ui.add_child(guide_beacon)
	_build_setup()
	_build_dice_overlay()
	faction_briefing = Briefing.new()
	faction_briefing.name = "FactionBriefing"
	ui.add_child(faction_briefing)
	faction_briefing.audio = audio
	faction_briefing.closed.connect(_on_briefing_closed)
	_build_sound_settings()
	_build_options_menu()

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _vbox(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	parent.add_child(box)
	return box

func _label(parent: Node, text: String, size: int = 16, color: Color = Color("e4f2fa")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _extraction_progress(parent: Node, finished: int, color: Color) -> void:
	var progress := ExtractionProgressScene.instantiate()
	parent.add_child(progress)
	progress.set_progress(finished, color)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _build_setup() -> void:
	setup_overlay = LobbyOverlayScene.instantiate()
	ui.add_child(setup_overlay)
	player_count = setup_overlay.find_child("PlayerCount", true, false) as OptionButton
	for count in [2, 3, 4]:
		player_count.add_item(tr("LOBBY_PLAYERS_COUNT").replace("{count}", str(count)), count)
	player_count.item_selected.connect(_update_setup.unbind(1))

	name_inputs.clear()
	_generated_lobby_names.clear()
	color_inputs.clear()
	player_rows.clear()
	for index in range(4):
		var row := setup_overlay.find_child("PlayerRow%d" % index, true, false) as HBoxContainer
		player_rows.append(row)
		var name_field := row.find_child("NameInput", true, false) as LineEdit
		name_field.placeholder_text = tr("LOBBY_PLAYER_NAME_PLACEHOLDER")
		name_field.text = tr("LOBBY_PLAYER_DEFAULT").replace("{n}", str(index + 1))
		name_inputs.append(name_field)
		_generated_lobby_names.append(name_field.text)
		var color_field := row.find_child("ColorInput", true, false) as OptionButton
		for team in range(4):
			color_field.add_item(Lore.profile(team).name, team)
		color_field.select(DEFAULT_COLORS[index])
		color_field.item_selected.connect(_preview_lobby_faction.bind(index).unbind(1))
		color_inputs.append(color_field)

	lobby_portrait = setup_overlay.find_child("LobbyPortrait", true, false) as Control
	lobby_faction_name = setup_overlay.find_child("FactionName", true, false) as Label
	lobby_character = setup_overlay.find_child("CharacterName", true, false) as Label
	lobby_description = setup_overlay.find_child("FactionDescription", true, false) as Label
	_preview_lobby_faction(0)

	fast_dice = setup_overlay.find_child("FastDice", true, false) as CheckBox
	setup_error = setup_overlay.find_child("SetupError", true, false) as Label
	var start_btn := setup_overlay.find_child("StartMatchButton", true, false) as Button
	start_btn.pressed.connect(_start_match)
	_update_setup()

func _update_setup() -> void:
	var count := player_count.get_selected_id()
	for index in range(4):
		player_rows[index].visible = index < count
	setup_error.text = ""

func show_lobby() -> void:
	if _busy:
		return
	_kill_pawn_tweens()
	game.phase = "lobby"
	_last_game_phase = "lobby"
	_host_faction = -1
	_host_player_name = ""
	_opening_player_name = ""
	_host_opens_match = true
	if is_instance_valid(faction_briefing):
		faction_briefing.hide()
	faction_card.hide()
	_selected = -1
	_view_player = -1
	camera.overview(false)
	_victory_shown = false
	_log.clear()
	_guide_event = ""
	_comms_id = ""
	_reaction_text = ""
	_reaction_until = 0
	comms_reveal.stop()
	sound_overlay.hide()
	history_label.text = ""
	setup_error.text = ""
	setup_overlay.show()
	dice_overlay.hide()
	if is_instance_valid(victory_overlay):
		victory_overlay.queue_free()
		victory_overlay = null
	_clear_highlights()
	for team in range(4):
		for pawn in range(4):
			var node: Piece = board.pawn_nodes[team][pawn]
			node.show()
			node.scale = Vector3.ONE * float(board.tile_spacing)
			node.position = board.jail_positions[team][pawn]
	for die_label in dice_labels:
		die_label.display(0, false, Color.WHITE)
	history_label.get_parent().hide()
	_clear_children(choices)
	turn_title.text = tr("HUD_AWAITING")
	turn_title.add_theme_color_override("font_color", Color("e4f2fa"))
	status.text = tr("HUD_SETUP_HINT")
	phase_badge.text = tr("HUD_SETUP")
	_clear_children(pawn_buttons)
	roll_button.disabled = true
	_clear_children(roster)
	_label(roster, tr("HUD_LOCAL"), 16, Color("6bdde5"))

func _start_match() -> void:
	var entries: Array[Dictionary] = []
	for index in range(player_count.get_selected_id()):
		entries.append({"name": name_inputs[index].text.strip_edges(), "color": color_inputs[index].get_selected_id()})
	if not game.configure(entries):
		setup_error.text = tr("LOBBY_INVALID")
		return
	setup_overlay.hide()
	_selected = -1
	_refresh()

func start_match_with_entries(entries: Array[Dictionary]) -> bool:
	if not game.configure(entries):
		return false
	for index in range(entries.size()):
		name_inputs[index].text = entries[index].name
		color_inputs[index].select(entries[index].color)
	player_count.select(entries.size() - 2)
	_update_setup()
	setup_overlay.hide()
	_selected = -1
	_refresh()
	return true

func _build_dice_overlay() -> void:
	dice_overlay = DiceOverlayScene.instantiate()
	ui.add_child(dice_overlay)
	dice_caption = dice_overlay.find_child("DiceCaption", true, false) as Label
	dice_viewport = dice_overlay.find_child("DiceViewport", true, false) as SubViewport
	dice_stage = DiceScene.instantiate()
	dice_viewport.add_child(dice_stage)
	dice_stage.sound_cue.connect(func(key: String):
		if key != "dice_impact": audio.play(key, int(game.players[game.current_player].color) if not game.players.is_empty() else -1))
	dice_stage.collision_cue.connect(func(strength: float): audio.play("dice_impact", int(game.players[game.current_player].color) if not game.players.is_empty() else -1, strength))
	dice_result = dice_overlay.find_child("DiceResult", true, false) as Label
	dice_stage.result_ready.connect(_dice_settled)
	dice_stage.animation_skipped.connect(_dice_animation_skipped)
	var skip_button := dice_overlay.find_child("SkipDiceAnimation", true, false) as Button
	skip_button.pressed.connect(func(): dice_stage.skip())
	dice_overlay.hide()

func _dice_animation_skipped() -> void:
	dice_overlay.hide()

func _dice_settled(values: Array[int]) -> void:
	var a := values[0]
	var b := values[1]
	_displayed_dice.assign(values)
	_update_dice_text()
	if a == b: audio.play("doubles")

func _roll_clicked() -> void:
	if _busy or _briefing_open() or _sound_settings_open() or game.phase not in ["opening", "await_roll"]:
		return
	guide.complete("opening" if game.phase == "opening" else "jail" if _all_jailed() else "roll")
	_busy = true
	_clear_highlights()
	_refresh()
	var player: Dictionary = game.players[game.current_player]
	_dice_player_name = str(player.name)
	_dice_opening = game.phase == "opening"
	_displayed_dice.clear()
	_update_dice_text()
	dice_result.text = tr("UI_ROLLING")
	dice_overlay.show()
	# Numeric result appears when the cubes have settled, not before the throw.
	var values: Array[int] = await dice_stage.play(board.player_colors[int(player.color)], fast_dice.button_pressed, _rng.randi())
	var a := values[0]
	var b := values[1]
	dice_overlay.hide()
	var previous_name := str(player.name)
	var was_opening := game.phase == "opening"
	game.roll(a, b)
	_add_log("LOG_OPENING_ROLL" if was_opening else "LOG_ROLL", [previous_name, a, b])
	_busy = false
	_refresh()
	if _selected >= 0:
		_focus_selected()

func _on_game_changed() -> void:
	var opening_finished := _last_game_phase == "opening" and game.phase == "await_roll"
	_last_game_phase = game.phase
	if _view_player != game.current_player:
		_selected = -1
		_view_player = game.current_player
		camera.overview()
		if game.phase != "opening": audio.play("turn")
	if _selected >= 0 and game.pawns[game.current_player][_selected] == Rules.FINISHED:
		_selected = -1
	_refresh()
	if game.phase == "bonus": _react("bonus", int(game.players[game.current_player].color))
	if opening_finished and _host_faction < 0:
		var first: Dictionary = game.players[game.current_player]
		_host_faction = local_faction_id if local_faction_id >= 0 else int(first.color)
		_host_player_name = str(first.name)
		_opening_player_name = str(first.name)
		_host_opens_match = _host_faction == int(first.color)
		for player in game.players:
			if local_faction_id >= 0 and int(player.color) == local_faction_id:
				_host_player_name = str(player.name)
		_show_faction_contact()
		faction_briefing.present(_host_faction, _host_player_name, _opening_player_name, _host_opens_match)
		_refresh()

func _refresh() -> void:
	if game.phase == "lobby":
		return
	_refresh_match_text()
	_sync_pawns()
	_rebuild_choices()
	_rebuild_highlights()
	if game.phase == "game_over" and not _victory_shown:
		_show_victory()

func _refresh_match_text() -> void:
	var player: Dictionary = game.players[game.current_player]
	var color: Color = board.player_colors[int(player.color)]
	turn_title.text = tr("HUD_OPENING_PLAYER") % player.name if game.phase == "opening" else str(player.name)
	turn_title.add_theme_color_override("font_color", color)
	_update_instruction()
	roll_button.disabled = _busy or _briefing_open() or game.phase not in ["opening", "await_roll"]
	roll_button.text = tr("UI_ROLL_FIRST") if game.phase == "opening" else (tr("UI_ROLL_DOUBLES") if _all_jailed() else tr("UI_ROLL_DICE"))
	lobby_button.disabled = _busy or _briefing_open()
	for index in range(2):
		dice_labels[index].display(int(game.last_roll[index]) if game.last_roll.size() == 2 else 0, game.dice_remaining[index] or game.phase == "opening", color)
		dice_labels[index].add_theme_color_override("font_color", color if game.dice_remaining[index] or game.phase == "opening" else Color("657f91"))
	_clear_children(roster)
	for index in range(game.players.size()):
		var entry: Dictionary = game.players[index]
		var profile := Lore.profile(int(entry.color))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		roster.add_child(row)
		var turn_marker := ColorRect.new()
		turn_marker.custom_minimum_size = Vector2(3, 38)
		turn_marker.color = profile.color if index == game.current_player else Color.TRANSPARENT
		turn_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(turn_marker)
		var portrait := preload("res://src/UI/components/AnimatedPortrait.gd").new()
		portrait.set_character(int(entry.color))
		portrait.custom_minimum_size = Vector2(38, 38)
		row.add_child(portrait)
		var emblem := TextureRect.new()
		emblem.texture = load(str(profile.emblem))
		emblem.custom_minimum_size = Vector2(22, 22)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.tooltip_text = str(profile.name)
		row.add_child(emblem)
		var details := _vbox(row)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 0)
		var name_label := _label(details, str(entry.name), 15, profile.color)
		name_label.clip_text = true
		name_label.custom_minimum_size.x = 0
		name_label.tooltip_text = str(entry.name)
		_extraction_progress(details, game.finished_count(index), profile.color)
	_update_faction_message()

func _kill_pawn_tweens() -> void:
	for team in range(4):
		for pawn in range(4):
			board.pawn_nodes[team][pawn].kill_movement()

func _sync_pawns() -> void:
	_kill_pawn_tweens()
	for team in range(4):
		var owner_index := -1
		for player in range(game.players.size()):
			if game.players[player].color == team:
				owner_index = player
		for pawn in range(4):
			var node: Piece = board.pawn_nodes[team][pawn]
			if owner_index < 0 or game.pawns[owner_index][pawn] == Rules.FINISHED:
				node.hide()
				continue
			node.show()
			var target := _pawn_position(owner_index, pawn)
			node.scale = Vector3.ONE * float(board.tile_spacing) * (1.0 if game.pawns[owner_index][pawn] == -1 else 0.73)
			if node.position.distance_to(target) > 0.01:
				node.move_smooth_to(target, 0.3)

func _position_for_progress(player: int, pawn: int, progress: int) -> Vector3:
	var team := int(game.players[player].color)
	if progress < 0:
		return board.jail_positions[team][pawn]
	if progress == Rules.FINISHED:
		return Vector3(0, 0.6, 0)
	if progress > Rules.TRACK_STEPS:
		return board.home_path_positions[team][progress - Rules.TRACK_STEPS - 1] + Vector3(0, 0.14, 0)
	return board.main_path_positions[game.circuit_index(player, progress)] + Vector3(0, 0.14, 0)

func _pawn_position(player: int, pawn: int) -> Vector3:
	var progress := int(game.pawns[player][pawn])
	var pos := _position_for_progress(player, pawn, progress)
	if progress < 0 or progress == Rules.FINISHED:
		return pos
	var occupants: Array[Vector2i] = []
	var target_cell := game.circuit_index(player, progress)
	for other in range(game.players.size()):
		for piece in range(4):
			var other_progress := int(game.pawns[other][piece])
			if (target_cell >= 0 and game.circuit_index(other, other_progress) == target_cell) or (target_cell < 0 and other == player and other_progress == progress):
				occupants.append(Vector2i(other, piece))
	if occupants.size() > 1:
		var slot := occupants.find(Vector2i(player, pawn))
		var angle := TAU * float(slot) / occupants.size()
		pos += Vector3(cos(angle), 0.04 * slot, sin(angle)) * 0.24 * float(board.tile_spacing)
	return pos

func _unhandled_input(event: InputEvent) -> void:
	if is_board_input_locked() or game.phase not in ["await_roll", "move", "bonus"]:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event.position as Vector2
		if _selected >= 0 and game.phase == "move":
			var closest_move: Dictionary = {}
			var distance := 24.0
			for move in game.legal_moves():
				if move.pawn != _selected:
					continue
				var destination := board.to_global(_position_for_progress(game.current_player, _selected, move.target))
				var screen := camera.unproject_position(destination)
				if screen.distance_to(mouse) < distance:
					distance = screen.distance_to(mouse)
					closest_move = move
			if not closest_move.is_empty():
				_execute_move(closest_move)
				return
		var selected := -1
		var nearest := 28.0
		var team := int(game.players[game.current_player].color)
		for pawn in range(4):
			if game.pawns[game.current_player][pawn] == Rules.FINISHED:
				continue
			var node: Piece = board.pawn_nodes[team][pawn]
			var screen := camera.unproject_position(node.global_position + Vector3(0, 0.4, 0))
			if screen.distance_to(mouse) < nearest:
				nearest = screen.distance_to(mouse)
				selected = pawn
		if selected >= 0:
			_select_pawn(selected)

func _movable_pawns() -> Array[int]:
	var result: Array[int] = []
	if game.phase == "bonus":
		for pawn in range(4):
			if game.pawns[game.current_player][pawn] != Rules.FINISHED:
				result.append(pawn)
	elif game.phase == "move":
		for move in game.legal_moves():
			if move.pawn not in result:
				result.append(move.pawn)
	return result

func _all_jailed() -> bool:
	if game.players.is_empty():
		return true
	for progress in game.pawns[game.current_player]:
		if progress >= 0 and progress != Rules.FINISHED:
			return false
	return true

func _update_instruction() -> void:
	phase_badge.text = {"opening": tr("PHASE_OPENING"), "await_roll": tr("PHASE_AWAIT_ROLL"), "move": tr("PHASE_LANDING") if _selected >= 0 else tr("PHASE_CREW"), "bonus": tr("PHASE_BONUS"), "game_over": tr("PHASE_GAME_OVER")}.get(game.phase, "")
	status.text = ""
	if _busy:
		phase_badge.text = tr("PHASE_ROLLING") if dice_stage.playing else tr("PHASE_TRANSIT")
	elif game.phase == "await_roll" and _all_jailed():
		status.text = tr("STATUS_JAIL_TRIES") % game.jail_attempts
	elif game.phase == "move" and _selected >= 0:
		if _selected not in _movable_pawns():
			status.text = tr("STATUS_JAIL") if game.pawns[game.current_player][_selected] < 0 else tr("STATUS_EXACT")
		else:
			status.text = tr("STATUS_CREW") % (_selected + 1)
	status.visible = not status.text.is_empty()

func _rebuild_choices() -> void:
	_clear_children(choices)
	_clear_children(pawn_buttons)
	focus_button.disabled = _selected < 0 or _busy or _briefing_open()
	if _busy or _briefing_open():
		return
	var movable := _movable_pawns()
	for pawn in range(4):
		var progress := int(game.pawns[game.current_player][pawn])
		var state := tr("PAWN_GOAL") if progress == Rules.FINISHED else (tr("PAWN_JAIL") if progress < 0 else tr("PAWN_READY") if pawn in movable else tr("PAWN_ON_BOARD"))
		var button := _button(pawn_buttons, tr("PAWN_DETAILS") % [pawn + 1, state], _select_pawn.bind(pawn))
		button.tooltip_text = str(board.pawn_nodes[int(game.players[game.current_player].color)][pawn].get_meta("callsign"))
		button.name = "Pawn%d" % (pawn + 1)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = progress == Rules.FINISHED or game.phase == "game_over"
		if pawn == _selected:
			button.add_theme_stylebox_override("normal", _style(Color("35402b"), Color("fff3a6")))
		elif pawn in movable:
			button.add_theme_stylebox_override("normal", _style(Color("16433c"), Color("9effb1")))
	if _selected < 0:
		return
	for move in game.legal_moves():
		if move.pawn != _selected:
			continue
		var destination := _destination_name(move.target)
		var text := tr("MOVE_RELEASE") % destination if move.kind == "release" else tr("MOVE_DETAILS") % [tr("MOVE_BOTH") if move.mask == 3 else "D%d" % (1 if move.mask == 1 else 2), move.steps, destination]
		var button := _button(choices, text, _execute_move.bind(move))
		button.add_theme_color_override("font_color", Color("b9ff75"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _destination_name(progress: int) -> String:
	if progress == Rules.GOAL:
		return tr("PAWN_GOAL")
	if progress > Rules.TRACK_STEPS:
		return tr("DEST_HOME") % (progress - Rules.TRACK_STEPS)
	return tr("DEST_CELL") % (game.circuit_index(game.current_player, progress) + 1)

func _select_pawn(pawn: int) -> void:
	if _busy or _briefing_open() or _sound_settings_open() or pawn < 0 or pawn > 3 or game.phase not in ["await_roll", "move", "bonus", "opening"]:
		return
	if game.pawns[game.current_player][pawn] == Rules.FINISHED:
		return
	if game.phase == "bonus":
		_execute_bonus(pawn)
		return
	audio.play("select")
	board.pawn_nodes[int(game.players[game.current_player].color)][pawn].acknowledge()
	_selected = pawn
	if pawn in _movable_pawns():
		guide.complete("select")
	_update_instruction()
	_rebuild_choices()
	_rebuild_highlights()
	_focus_selected()

func _focus_selected() -> void:
	if _selected < 0 or game.phase in ["lobby", "game_over"]:
		return
	var points: Array[Vector3] = [board.to_global(_pawn_position(game.current_player, _selected))]
	for move in game.legal_moves():
		if move.pawn == _selected:
			points.append(board.to_global(_position_for_progress(game.current_player, _selected, move.target)))
	camera.focus_points(points)

func _pawn_glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, 0.3)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8
	return material

func _clear_highlights() -> void:
	_clear_children(highlights)
	if is_instance_valid(move_overlay):
		move_overlay.set_pins([])
		move_overlay.route.clear()
	for team in range(4):
		for pawn in range(4):
			for child in board.pawn_nodes[team][pawn].find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D:
					child.material_overlay = null

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _rebuild_highlights() -> void:
	_clear_highlights()
	if _busy or _briefing_open() or game.phase in ["lobby", "game_over"]:
		return
	var team := int(game.players[game.current_player].color)
	var movable := _movable_pawns()
	var pins: Array[Dictionary] = []
	for pawn in range(4):
		if game.pawns[game.current_player][pawn] == Rules.FINISHED:
			continue
		var can_move := pawn in movable
		var selected := pawn == _selected
		var color := Color("fff3a6") if selected else Color("79ffff") if can_move else Color("7a93ab")
		var pos := _pawn_position(game.current_player, pawn)
		pins.append({"id": "pawn_%d" % pawn, "kind": "pawn", "text": str(pawn + 1), "color": color, "world": board.to_global(pos + Vector3(0, 0.65, 0)), "tooltip": tr("PAWN_TOOLTIP") % [board.pawn_nodes[team][pawn].get_meta("callsign"), pawn + 1, tr("PAWN_CAN_MOVE") if can_move else tr("PAWN_INSPECT")]})
		if can_move or selected:
			_marker(pos, color, 0.46)
			for child in board.pawn_nodes[team][pawn].find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D:
					child.material_overlay = _selected_glow if selected else _glow_material
	var max_steps := 0
	if _selected >= 0 and game.phase == "move":
		var moves := game.legal_moves()
		for index in range(moves.size()):
			var move: Dictionary = moves[index]
			if move.pawn != _selected:
				continue
			var pos := _position_for_progress(game.current_player, _selected, move.target)
			_marker(pos, Color("b9ff75"), 0.47)
			pins.append({"id": "move_%d" % index, "kind": "move", "text": tr("MOVE_LAUNCH") if move.kind == "release" else "+%d" % move.steps, "color": Color("b9ff75"), "world": board.to_global(pos), "tooltip": _destination_name(move.target)})
			max_steps = maxi(max_steps, move.steps)
		if max_steps > 0:
			var start := int(game.pawns[game.current_player][_selected])
			for progress in range(start, start + max_steps + 1):
				move_overlay.route.append(board.to_global(_position_for_progress(game.current_player, _selected, progress)))
	move_overlay.set_pins(pins)

func _marker(pos: Vector3, color: Color, radius: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = (radius - 0.055) * float(board.tile_spacing)
	ring.outer_radius = (radius + 0.055) * float(board.tile_spacing)
	var mesh := MeshInstance3D.new()
	mesh.mesh = ring
	mesh.position = pos + Vector3(0, 0.08, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.25
	mesh.material_override = material
	highlights.add_child(mesh)

func _pin_picked(id: String) -> void:
	if _busy or _briefing_open() or _sound_settings_open():
		return
	if id.begins_with("pawn_"):
		_select_pawn(int(id.trim_prefix("pawn_")))
	elif id.begins_with("move_"):
		var index := int(id.trim_prefix("move_"))
		var moves := game.legal_moves()
		if index >= 0 and index < moves.size() and moves[index].pawn == _selected:
			_execute_move(moves[index])

func _update_cell_info() -> void:
	if not is_instance_valid(cell_info) or setup_overlay.visible or dice_overlay.visible:
		return
	var mouse := get_viewport().get_mouse_position()
	if not get_play_rect().has_point(mouse):
		return
	var point: Variant = camera.ground_at(mouse)
	if point is not Vector3:
		return
	var local: Vector3 = board.to_local(point)
	for index in range(board.main_path_positions.size()):
		if Vector2(local.x, local.z).distance_to(Vector2(board.main_path_positions[index].x, board.main_path_positions[index].z)) < float(board.tile_spacing) * 0.48:
			cell_info.text = tr("CELL_INFO") % [index + 1, tr("CELL_LAUNCH") if index in board.launch_indices else tr("CELL_SAFE") if index in board.safe_indices else tr("CELL_EXPOSED")]
			return
	cell_info.text = ""

func _execute_move(move: Dictionary) -> void:
	if _busy or _briefing_open() or _sound_settings_open() or game.phase != "move":
		return
	var valid := false
	for legal in game.legal_moves():
		if legal == move:
			valid = true
	if not valid:
		return
	_busy = true
	_clear_highlights()
	_refresh()
	_kill_pawn_tweens()
	var player := game.current_player
	var team := int(game.players[player].color)
	var node: Piece = board.pawn_nodes[team][int(move.pawn)]
	var color: Color = board.player_colors[team]
	audio.play("launch" if move.kind == "release" else "travel", team)
	effects.follow(node, color)
	effects.burst(node.position, color)
	if move.kind == "release":
		await node.move_release_to(_position_for_progress(player, move.pawn, 0))
	else:
		var start := int(game.pawns[player][int(move.pawn)])
		var waypoints: Array[Vector3] = []
		for progress in range(start + 1, int(move.target) + 1):
			waypoints.append(_position_for_progress(player, move.pawn, progress))
		await node.move_steps_to(waypoints, _position_for_progress(player, move.pawn, move.target))
	audio.play("finish" if int(move.target) == Rules.FINISHED else "land")
	effects.stop(node)
	effects.burst(node.position, color)
	guide.complete("release" if move.kind == "release" else "move")
	if move.kind == "release": _react("launch", team)
	var name_tag := str(game.players[player].name)
	# Snapshot the destination before the rules recall captured rivals.
	var impact := node.position
	game.play(move.pawn, move.mask)
	if int(move.target) == Rules.FINISHED:
		_guide_notice("finish")
		_react("finish", team)
	elif int(move.target) > Rules.TRACK_STEPS:
		_guide_notice("home")
	elif move.kind != "release" and board.is_protected_cell(game.circuit_index(player, int(move.target))):
		audio.play("shield")
		_guide_notice("safe")
		_react("shield", team)
	if move.kind == "release":
		_add_log("LOG_RELEASE", [name_tag, int(move.pawn) + 1])
	else:
		_add_log("LOG_MOVE", [name_tag, int(move.pawn) + 1, move.steps])
	if not game.captured.is_empty():
		_add_log("LOG_CAPTURE", [game.captured.size()])
		audio.play("capture")
		_guide_notice("capture")
		_react("capture", team)
		effects.burst(impact + Vector3(0, .4, 0), Color("ffb4a8"))
	_busy = false
	_refresh()

func _execute_bonus(pawn: int) -> void:
	if _busy or _briefing_open() or _sound_settings_open() or game.phase != "bonus":
		return
	_busy = true
	_refresh()
	_kill_pawn_tweens()
	var team := int(game.players[game.current_player].color)
	var node: Piece = board.pawn_nodes[team][pawn]
	audio.play("launch", team)
	await node.move_bonus_to(Vector3(0, 0.6, 0))
	effects.burst(Vector3(0, .5, 0), board.player_colors[team])
	audio.play("finish")
	guide.complete("bonus")
	_react("finish", team)
	game.claim_bonus(pawn)
	_add_log("LOG_BONUS", [pawn + 1])
	_busy = false
	_refresh()

func _add_log(key: String, values: Array = []) -> void:
	history_label.get_parent().visible = _details_open
	_log.append({"key": key, "values": values})
	while _log.size() > 3:
		_log.pop_front()
	_refresh_history()

func _show_victory() -> void:
	_victory_shown = true
	audio.play("victory")
	victory_overlay = VictoryOverlayScene.instantiate()
	ui.add_child(victory_overlay)
	var team := int(game.players[game.winner].color)
	var portrait := victory_overlay.find_child("VictoryPortrait", true, false) as Control
	portrait.set_character(team, "celebrate")
	effects.burst(Vector3(0, .6, 0), board.player_colors[team])
	var title_lbl := victory_overlay.find_child("TitleLabel", true, false) as Label
	title_lbl.add_theme_color_override("font_color", board.player_colors[team])
	var winner_lbl := victory_overlay.find_child("WinnerLabel", true, false) as Label
	winner_lbl.text = tr("VICTORY_WINNER") % game.players[game.winner].name
	var rematch_btn := victory_overlay.find_child("RematchButton", true, false) as Button
	rematch_btn.pressed.connect(show_lobby)

func _briefing_open() -> bool:
	return faction_briefing.visible

func is_board_input_locked() -> bool:
	return _busy or _briefing_open() or _options_menu_open() or sound_overlay.visible or setup_overlay.visible or dice_overlay.visible

func _preview_lobby_faction(seat: int) -> void:
	var faction := Lore.profile(color_inputs[seat].get_selected_id())
	lobby_portrait.set_character(int(faction.id), "calm")
	lobby_faction_name.text = faction.name
	lobby_faction_name.add_theme_color_override("font_color", faction.color)
	lobby_character.text = "%s %s" % [str(faction.title).capitalize(), faction.character]
	lobby_description.text = faction.description

func _show_faction_contact() -> void:
	var faction := Lore.profile(_host_faction)
	faction_portrait.set_character(_host_faction, "calm")
	faction_heading.text = str(faction.name).to_upper()
	faction_heading.add_theme_color_override("font_color", faction.color)
	faction_speaker.text = "%s %s" % [str(faction.title).capitalize(), faction.character]
	faction_card.show()

func replay_briefing() -> void:
	if _busy or _host_faction < 0 or game.phase in ["lobby", "opening", "game_over"] or _briefing_open():
		return
	faction_briefing.present(_host_faction, _host_player_name, _opening_player_name, _host_opens_match)
	_refresh()

func _on_briefing_closed() -> void:
	_refresh()
	if _selected >= 0:
		_focus_selected()

func _update_faction_message() -> void:
	_refresh_guidance()

func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.name = "OrbitalPainting"
	add_child(layer)
	var art := TextureRect.new()
	art.texture = preload("res://assets/loom-background.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var environment: Environment = get_node("WorldEnvironment").environment
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = -1

func _refresh_guidance() -> void:
	if is_instance_valid(guide_beacon):
		guide_beacon.target = null
	if is_board_input_locked() or game.phase == "game_over" or game.players.is_empty():
		faction_card.hide()
		return
	var key := ""
	if not _guide_event.is_empty() and _clock < _guide_event_until and not guide.seen.has(_guide_event):
		key = _guide_event
	elif game.phase == "opening":
		key = "opening"
	elif game.phase == "await_roll":
		key = "jail" if _all_jailed() else "roll"
	elif game.phase == "bonus":
		key = "bonus"
	elif game.phase == "move":
		var has_release := false
		for move in game.legal_moves():
			has_release = has_release or move.kind == "release"
		key = "release" if has_release else "select" if _selected < 0 else "move"
	var text := guide.cue(key)
	if text.is_empty() and _clock < _reaction_until and not _reaction_text.is_empty():
		key = "reaction"
		text = _reaction_text
	faction_card.visible = not text.is_empty()
	if text.is_empty():
		return
	var team := _reaction_team if key == "reaction" else (_host_faction if _host_faction >= 0 else int(game.players[game.current_player].color))
	var faction := Lore.profile(team)
	faction_portrait.set_character(team, "resolve" if key in ["release", "bonus", "capture", "finish", "home", "reaction"] else "calm")
	faction_heading.text = tr("GUIDANCE_TITLE")
	faction_heading.add_theme_color_override("font_color", faction.color)
	faction_speaker.text = faction.character
	faction_speaker.add_theme_font_size_override("font_size", 15)
	var message_id := "%d:%s:%s" % [team, key, text]
	if _comms_id != message_id:
		_comms_id = message_id
		comms_reveal.begin(faction_message, text)
		audio.play("comms", team)
	if key in ["opening", "jail", "roll"]:
		guide_beacon.target = roll_button
	elif key in ["select", "move", "release", "bonus"]:
		var destination: Control
		var crew: Control
		for pin in move_overlay.pins:
			var control := move_overlay.get_node_or_null(str(pin.id)) as Control
			if pin.kind == "move" and not is_instance_valid(destination):
				destination = control
			if pin.kind == "pawn" and int(str(pin.id).trim_prefix("pawn_")) in _movable_pawns() and not is_instance_valid(crew):
				crew = control
		guide_beacon.target = destination if is_instance_valid(destination) else crew
	guide_dismiss.text = tr("GUIDANCE_CLOSE") if key == "reaction" else tr("GUIDANCE_UNDERSTOOD") if key in ["safe", "capture", "home", "finish", "camera"] else tr("GUIDANCE_HIDE")

func _guide_notice(key: String) -> void:
	if not guide.seen.has(key):
		_guide_event = key
		_guide_event_until = _clock + 18

func _dismiss_guidance() -> void:
	if guide.active.is_empty():
		_reaction_until = 0
		_reaction_text = ""
	elif guide.active in ["safe", "capture", "home", "finish", "camera"]:
		guide.complete(guide.active)
	else:
		guide.enabled = false
		guide.save()
	_refresh_guidance()

func _menu_action(id: int) -> void:
	match id:
		0: replay_briefing()
		1:
			guide.reset()
			_refresh_guidance()
		2:
			_details_open = not _details_open
			settings.get_popup().set_item_checked(settings.get_popup().get_item_index(id), _details_open)
			pawn_buttons.visible = _details_open
			choices.visible = _details_open
			history_label.get_parent().visible = _details_open
		3:
			board.set_coordinates_visible(not board.coordinates_visible)
			settings.get_popup().set_item_checked(settings.get_popup().get_item_index(id), board.coordinates_visible)
		4:
			guide.enabled = true
			guide.seen.erase("camera")
			_guide_notice("camera")
		5:
			audio.set_muted(audio.enabled)
			settings.get_popup().set_item_checked(settings.get_popup().get_item_index(id), not audio.enabled)
		6:
			_open_sound_settings()
		7:
			_open_options_menu()

func _build_sound_settings() -> void:
	sound_overlay = SoundSettingsOverlayScene.instantiate()
	ui.add_child(sound_overlay)
	var effects_slider := sound_overlay.find_child("EffectsVolume", true, false) as HSlider
	effects_slider.value = audio.effects_volume
	effects_slider.value_changed.connect(func(val: float): audio.set_volume("effects", val))
	var dialogue_slider := sound_overlay.find_child("DialogueVolume", true, false) as HSlider
	dialogue_slider.value = audio.dialogue_volume
	dialogue_slider.value_changed.connect(func(val: float): audio.set_volume("dialogue", val))

	var mute := sound_overlay.find_child("MuteAudio", true, false) as CheckBox
	mute.button_pressed = not audio.enabled
	mute.toggled.connect(func(value: bool):
		audio.set_muted(value)
		settings.get_popup().set_item_checked(settings.get_popup().get_item_index(5), value)
	)

	var motion := sound_overlay.find_child("PortraitMotion", true, false) as CheckBox
	motion.button_pressed = audio.portrait_motion
	motion.toggled.connect(func(value: bool):
		audio.portrait_motion = value
		audio.save_preferences()
	)

	var preview_btn := sound_overlay.find_child("PreviewButton", true, false) as Button
	preview_btn.pressed.connect(func(): audio.play("shield"))
	var done_btn := sound_overlay.find_child("DoneButton", true, false) as Button
	done_btn.pressed.connect(func(): sound_overlay.hide())
	sound_overlay.hide()

func _open_sound_settings() -> void:
	if _busy or _briefing_open() or setup_overlay.visible:
		return
	var mute := sound_overlay.find_child("MuteAudio", true, false) as CheckBox
	mute.set_pressed_no_signal(not audio.enabled)
	sound_overlay.show()
	sound_overlay.find_child("EffectsVolume", true, false).grab_focus()

func _sound_settings_open() -> bool:
	return sound_overlay.visible

func _build_options_menu() -> void:
	options_overlay = OptionsMenuScene.instantiate()
	ui.add_child(options_overlay)
	options_overlay.set_in_game_mode(true)
	options_overlay.back_pressed.connect(_close_options_menu)
	options_overlay.hide()

func _open_options_menu() -> void:
	if _busy or _briefing_open() or setup_overlay.visible:
		return
	options_overlay.show()

func _close_options_menu() -> void:
	options_overlay.hide()

func _options_menu_open() -> bool:
	return options_overlay.visible

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _options_menu_open():
			_close_options_menu()
			get_viewport().set_input_as_handled()
		elif _sound_settings_open():
			sound_overlay.hide()
			get_viewport().set_input_as_handled()
		elif not setup_overlay.visible and game.phase != "lobby" and not _busy and not _briefing_open():
			_open_options_menu()
			get_viewport().set_input_as_handled()

func _react(event: String, team: int) -> void:
	_comms_id = ""
	_reaction_event = event
	_reaction_text = Lore.reaction(team, event)
	_reaction_until = _clock + 5
	_reaction_team = team

func _refresh_history() -> void:
	var lines: PackedStringArray = []
	for entry in _log:
		lines.append(tr(entry.key) % entry.values)
	history_label.text = "\n".join(lines)

func _update_dice_text() -> void:
	dice_caption.text = "%s / %s" % [_dice_player_name, tr("DICE_STARTING_ORDER") if _dice_opening else tr("DICE_REACTOR")]
	if _displayed_dice.size() == 2:
		var a := _displayed_dice[0]
		var b := _displayed_dice[1]
		dice_result.text = "%d  +  %d  =  %d%s" % [a, b, a + b, tr("DICE_DOUBLES_SUFFIX") if a == b else ""]
	else:
		dice_result.text = tr("UI_ROLLING")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_translations()

func _refresh_translations() -> void:
	var menu_keys := ["MENU_PROLOGUE", "MENU_RESTART_GUIDANCE", "MENU_MOVE_LIST", "MENU_COORDINATES", "MENU_CAMERA_CONTROLS", "MENU_MUTE_SOUND", "MENU_AUDIO_SETTINGS", "MENU_GENERAL_OPTIONS"]
	for index in range(menu_keys.size()):
		settings.get_popup().set_item_text(index, tr(menu_keys[index]))
	for index in range(player_count.item_count):
		player_count.set_item_text(index, tr("LOBBY_PLAYERS_COUNT").format({"count": player_count.get_item_id(index)}))
	for index in range(name_inputs.size()):
		if name_inputs[index].text == _generated_lobby_names[index]:
			_generated_lobby_names[index] = tr("LOBBY_PLAYER_DEFAULT").format({"n": index + 1})
			name_inputs[index].text = _generated_lobby_names[index]
		name_inputs[index].placeholder_text = tr("LOBBY_PLAYER_NAME_PLACEHOLDER")
		for team in range(4):
			color_inputs[index].set_item_text(team, Lore.profile(team).name)
	if not setup_error.text.is_empty():
		setup_error.text = tr("LOBBY_INVALID")
	_preview_lobby_faction(0)
	_refresh_history()
	_update_dice_text()
	if not _reaction_event.is_empty():
		_reaction_text = Lore.reaction(_reaction_team, _reaction_event)
	if game.phase == "lobby":
		turn_title.text = tr("HUD_AWAITING")
		status.text = tr("HUD_SETUP_HINT")
		phase_badge.text = tr("HUD_SETUP")
		if roster.get_child_count() > 0:
			roster.get_child(0).text = tr("HUD_LOCAL")
	else:
		_refresh_match_text()
		_rebuild_choices()
		_rebuild_highlights()
	if is_instance_valid(victory_overlay):
		victory_overlay.find_child("WinnerLabel", true, false).text = tr("VICTORY_WINNER") % game.players[game.winner].name
