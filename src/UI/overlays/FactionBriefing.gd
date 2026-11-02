extends Control
## Reusable presentation layer: caller provides the viewer's faction and name.
## Today the caller chooses the opening winner; future clients can supply their own.
signal closed
const Lore := preload("res://Factions.gd")
var faction_id := -1
var page_index := 0
var pages: Array[Dictionary] = []
var portrait: Control
var faction_name: Label
var speaker: Label
var motto: Label
var page_title: Label
var dialogue: RichTextLabel
var progress: Label
var next_button: Button
var back_button: Button
var _accent := Color.WHITE
var _opens_match := true
var _player_name := ""
var _opening_player_name := ""
var emblem: TextureRect
var _reveal: Tween
var reveal: Node
var audio: Node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	var art := TextureRect.new()
	art.texture = preload("res://assets/loom-background.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.004, 0.009, 0.022, 0.55)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.name = "TransmissionPanel"
	panel.custom_minimum_size = Vector2(1000, 560)
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, .045, .07, .85), Color("406274")))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	emblem = TextureRect.new()
	emblem.custom_minimum_size = Vector2(32, 32)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(emblem)
	faction_name = _label(header, "", 23)
	faction_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress = _label(header, "", 15, Color("8facbf"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var character_box := VBoxContainer.new()
	row.add_child(character_box)
	portrait = preload("res://src/UI/components/AnimatedPortrait.gd").new()
	portrait.custom_minimum_size = Vector2(320, 320)
	character_box.add_child(portrait)
	speaker = _label(character_box, "", 22)
	motto = _label(character_box, "", 15, Color("a7becd"))
	motto.custom_minimum_size.x = 320
	motto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dialogue_box := VBoxContainer.new()
	dialogue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_box.add_theme_constant_override("separation", 16)
	row.add_child(dialogue_box)
	page_title = _label(dialogue_box, "", 24)
	page_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_title.custom_minimum_size.x = 560
	dialogue = RichTextLabel.new()
	dialogue.bbcode_enabled = false
	dialogue.custom_minimum_size = Vector2(560, 280)
	dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue.add_theme_font_size_override("normal_font_size", 21)
	dialogue.add_theme_color_override("default_color", Color("dcebf4"))
	dialogue.scroll_active = true
	dialogue_box.add_child(dialogue)
	dialogue.tooltip_text = tr("UI_TOOLTIP_TRANSMISSION")
	dialogue.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			reveal.complete()
	)
	reveal = preload("res://src/UI/components/DialogueReveal.gd").new()
	add_child(reveal)
	reveal.tick.connect(func():
		if is_instance_valid(audio): audio.play("text", faction_id)
	)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	var skip := _button(footer, "UI_SKIP_PROLOGUE", finish)
	skip.name = "SkipBriefing"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	back_button = _button(footer, "UI_BACK", previous_page)
	back_button.name = "PreviousPage"
	next_button = _button(footer, tr("UI_CONTINUE"), next_page)
	next_button.name = "NextPage"
	hide()

func present(viewer_faction: int, player_name: String, opening_player_name: String = "", opens_match: bool = true) -> void:
	_player_name = player_name
	_opening_player_name = opening_player_name
	_opens_match = opens_match
	faction_id = viewer_faction
	page_index = 0
	_refresh_content()
	portrait.set_character(faction_id, "resolve")
	_update_page()
	show()
	next_button.grab_focus()
	if _reveal and _reveal.is_valid():
		_reveal.kill()
	portrait.modulate.a = 0
	reveal.begin(dialogue, dialogue.text, 140)
	if is_instance_valid(audio): audio.play("comms", faction_id)
	_reveal = create_tween().set_parallel()
	_reveal.tween_property(portrait, "modulate:a", 1.0, .6)


func _refresh_content() -> void:
	var faction := Lore.profile(faction_id)
	_accent = faction.color
	emblem.texture = load(str(faction.emblem))
	var turn_guide: String = tr("PROLOGUE_FIRST_TURN_SELF") if _opens_match else tr("PROLOGUE_FIRST_TURN_OTHER").replace("{first}", _opening_player_name)
	var intro_text := tr("PROLOGUE_INTRO_BODY").replace("{player}", _player_name).replace("{expedition}", Lore.expedition(faction_id)).replace("{turn_guide}", turn_guide)
	pages = [{"title": tr("PROLOGUE_TITLE"), "text": intro_text}]
	faction_name.text = tr("PROLOGUE_HEADER").replace("{name}", str(faction.name).to_upper())
	faction_name.add_theme_color_override("font_color", _accent)
	speaker.text = "%s %s" % [str(faction.title).capitalize(), faction.character]
	speaker.add_theme_color_override("font_color", _accent)
	motto.text = faction.motto

func _update_page() -> void:
	page_title.text = pages[page_index].title
	dialogue.text = pages[page_index].text
	dialogue.scroll_to_line(0)
	progress.text = tr("PROLOGUE_BADGE")
	back_button.hide()
	back_button.disabled = page_index == 0
	next_button.text = (tr("UI_BEGIN_TURN") if _opens_match else tr("UI_ENTER_ARENA")) if page_index == pages.size() - 1 else tr("UI_CONTINUE")

func next_page() -> void:
	if not visible:
		return
	if page_index + 1 >= pages.size():
		finish()
	else:
		page_index += 1
		_update_page()

func previous_page() -> void:
	if visible and page_index > 0:
		page_index -= 1
		_update_page()

func finish() -> void:
	if not visible:
		return
	reveal.stop()
	portrait.speaking = false
	if _reveal and _reveal.is_valid(): _reveal.kill()
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		finish()
		get_viewport().set_input_as_handled()

func _label(parent: Node, text: String, size: int, color: Color = Color("e4f2fa")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 18)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	return style

func _process(_delta: float) -> void:
	if is_instance_valid(reveal) and is_instance_valid(portrait):
		portrait.speaking = visible and reveal.revealing

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and faction_id >= 0:
		_refresh_content()
		_update_page()
		dialogue.tooltip_text = tr("UI_TOOLTIP_TRANSMISSION")
		if visible:
			reveal.begin(dialogue, dialogue.text, 140)
