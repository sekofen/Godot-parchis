extends Control
class_name LocalSetup

signal back_pressed
signal start_game(players_data: Array[Dictionary])

@onready var player_count_option: OptionButton = %PlayerCountOption
@onready var slots_container: VBoxContainer = %SlotsContainer
@onready var btn_back: Button = %BtnBack
@onready var btn_start: Button = %BtnStart
@onready var status_label: Label = %StatusLabel

const PlayerSlotScene := preload("res://src/UI/menus/PlayerSlot.tscn")
const DEFAULT_COLORS: Array[int] = [0, 2, 1, 3]

var slot_instances: Array[PlayerSlot] = []
var _status_key := ""
var _status_values: Array = []

func _ready() -> void:
	_setup_count_options()
	_create_slots()
	player_count_option.item_selected.connect(_on_count_changed)
	btn_back.pressed.connect(_on_back_pressed)
	btn_start.pressed.connect(_on_start_pressed)
	_update_slot_visibility()

func _setup_count_options() -> void:
	player_count_option.clear()
	for count in [2, 3, 4]:
		player_count_option.add_item(tr("LOBBY_PLAYERS_COUNT").format({"count": count}), count)
	player_count_option.select(2) # Default 4 players

func _create_slots() -> void:
	# Clear existing children if any
	for child in slots_container.get_children():
		child.queue_free()
	slot_instances.clear()
	
	for i in range(4):
		var slot: PlayerSlot = PlayerSlotScene.instantiate()
		slots_container.add_child(slot)
		slot.configure(i, "", DEFAULT_COLORS[i])
		slot.data_changed.connect(_on_slot_data_changed)
		slot_instances.append(slot)

func _on_count_changed(_index: int) -> void:
	_update_slot_visibility()

func _update_slot_visibility() -> void:
	var count: int = get_selected_player_count()
	for i in range(slot_instances.size()):
		slot_instances[i].visible = (i < count)
	_set_status("")

func get_selected_player_count() -> int:
	return player_count_option.get_selected_id()

func _on_slot_data_changed() -> void:
	_set_status("")

func _on_back_pressed() -> void:
	print("[LocalSetup] Returning to main menu...")
	back_pressed.emit()

func _on_start_pressed() -> void:
	var count := get_selected_player_count()
	var players: Array[Dictionary] = []
	var chosen_colors: Array[int] = []
	
	for i in range(count):
		var data: Dictionary = slot_instances[i].get_player_data()
		if data.name.is_empty():
			_set_status("SETUP_NAME_REQUIRED", [i + 1])
			return
		if chosen_colors.has(data.faction_id):
			_set_status("SETUP_UNIQUE_FACTIONS")
			return
		chosen_colors.append(data.faction_id)
		players.append(data)
	
	_set_status("")
	
	print("[LocalSetup] Starting local match with %d players" % count)
	
	start_game.emit(players)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for index in range(player_count_option.item_count):
			player_count_option.set_item_text(index, tr("LOBBY_PLAYERS_COUNT").format({"count": player_count_option.get_item_id(index)}))
		status_label.text = tr(_status_key) % _status_values if not _status_key.is_empty() else ""

func _set_status(key: String, values: Array = []) -> void:
	_status_key = key
	_status_values = values
	status_label.text = tr(key) % values if not key.is_empty() else ""
