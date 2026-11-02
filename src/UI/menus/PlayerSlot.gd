extends HBoxContainer
class_name PlayerSlot

signal data_changed

@onready var number_label: Label = $NumberLabel
@onready var name_input: LineEdit = $NameInput
@onready var faction_option: OptionButton = $FactionOption
@onready var role_badge: Label = $RoleBadge

const Lore := preload("res://Factions.gd")
const COLOR_KEYS := ["COLOR_RED", "COLOR_GREEN", "COLOR_BLUE", "COLOR_YELLOW"]
const DEFAULT_COLORS: Array[int] = [0, 2, 1, 3]
var slot_index: int = 0
var is_waiting_connection: bool = false
var _name_key := "SLOT_DEFAULT_NAME"
var _generated_name := ""
var _role_key := ""

static func faction_label(faction_id: int) -> String:
	return "%s (%s)" % [Lore.profile(faction_id).name, TranslationServer.translate(COLOR_KEYS[faction_id])]

func _ready() -> void:
	_populate_factions()
	name_input.text_changed.connect(func(_new_text: String) -> void: data_changed.emit())
	faction_option.item_selected.connect(func(_idx: int) -> void: data_changed.emit())

func _populate_factions() -> void:
	var selected := faction_option.get_selected_id()
	faction_option.clear()
	for i in range(4):
		faction_option.add_item(faction_label(i), i)
	faction_option.select(maxi(0, selected))

func _default_name() -> String:
	return tr(_name_key) % (slot_index + 1) if _name_key == "SLOT_DEFAULT_NAME" else tr(_name_key)

func configure(index: int, default_name: String = "", default_faction: int = -1, name_key: String = "SLOT_DEFAULT_NAME") -> void:
	slot_index = index
	_name_key = name_key
	is_waiting_connection = false
	_populate_factions()
	number_label.text = "%02d" % (index + 1)
	name_input.editable = true
	_generated_name = _default_name() if default_name.is_empty() else ""
	name_input.text = _generated_name if default_name.is_empty() else default_name
	name_input.placeholder_text = tr("SLOT_NAME_PLACEHOLDER") % (index + 1)
	faction_option.disabled = false
	var chosen_color := default_faction if default_faction >= 0 else DEFAULT_COLORS[index % DEFAULT_COLORS.size()]
	faction_option.select(chosen_color)

func set_waiting_state() -> void:
	is_waiting_connection = true
	name_input.text = ""
	_generated_name = ""
	name_input.placeholder_text = tr("SLOT_WAIT_PLACEHOLDER")
	name_input.editable = false
	faction_option.disabled = true
	set_role_tag("SLOT_WAITING", false)

func receive_remote_player(player_name: String, faction_id: int = -1) -> void:
	is_waiting_connection = false
	_generated_name = ""
	name_input.text = player_name
	name_input.editable = false # Only the remote player can rename themselves.
	name_input.placeholder_text = tr("SLOT_NAME_PLACEHOLDER") % (slot_index + 1)
	if faction_id >= 0:
		faction_option.select(faction_id)
	faction_option.disabled = true
	set_role_tag("SLOT_CONNECTED", true)
	data_changed.emit()

func set_role_tag(tag_key: String, is_accent: bool = false) -> void:
	_role_key = tag_key
	role_badge.visible = not tag_key.is_empty()
	role_badge.text = tr(tag_key) if not tag_key.is_empty() else ""
	role_badge.modulate = Color(0.41, 0.89, 0.92, 1.0) if is_accent else Color(0.65, 0.65, 0.7, 0.8)

func get_player_data() -> Dictionary:
	return {
		"seat": slot_index,
		"name": name_input.text.strip_edges(),
		"faction_id": faction_option.get_selected_id(),
		"is_connected": not is_waiting_connection
	}

func set_editable(enabled: bool) -> void:
	name_input.editable = enabled
	faction_option.disabled = not enabled

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_populate_factions()
		if not _generated_name.is_empty() and name_input.text == _generated_name:
			_generated_name = _default_name()
			name_input.text = _generated_name
		name_input.placeholder_text = tr("SLOT_WAIT_PLACEHOLDER") if is_waiting_connection else tr("SLOT_NAME_PLACEHOLDER") % (slot_index + 1)
		role_badge.text = tr(_role_key) if not _role_key.is_empty() else ""
