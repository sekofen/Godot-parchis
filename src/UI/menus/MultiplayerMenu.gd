extends Control
class_name MultiplayerMenu

signal back_to_main_requested
signal host_started(config: Dictionary)
signal join_requested(room_code: String, player_data: Dictionary)

# Views
@onready var mode_select_view: VBoxContainer = %ModeSelectView
@onready var host_view: VBoxContainer = %HostView
@onready var join_view: VBoxContainer = %JoinView

# Mode selection buttons
@onready var btn_choose_host: Button = %BtnChooseHost
@onready var btn_choose_join: Button = %BtnChooseJoin
@onready var btn_back_to_main: Button = %BtnBackToMain

# Host controls
@onready var room_code_display: LineEdit = %RoomCodeDisplay
@onready var btn_copy_code: Button = %BtnCopyCode
@onready var host_player_count: OptionButton = %HostPlayerCount
@onready var host_slots_container: VBoxContainer = %HostSlotsContainer
@onready var host_status_label: Label = %HostStatusLabel
@onready var btn_simulate_player: Button = %BtnSimulatePlayer
@onready var btn_host_back: Button = %BtnHostBack
@onready var btn_host_start: Button = %BtnHostStart

# Join controls
@onready var join_name_input: LineEdit = %JoinNameInput
@onready var join_faction_option: OptionButton = %JoinFactionOption
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var join_status_label: Label = %JoinStatusLabel
@onready var btn_join_back: Button = %BtnJoinBack
@onready var btn_connect: Button = %BtnConnect

const PlayerSlotScene := preload("res://src/UI/menus/PlayerSlot.tscn")
const SIMULATED_ROOM_CODE := "PARQUE-4821"
const DEFAULT_COLORS: Array[int] = [0, 2, 1, 3]

# Simulated incoming remote player pool
const SIMULATED_REMOTE_NAMES: Array[String] = ["Camila_Uni", "Mateo_99", "Sara_G"]

var host_slot_instances: Array[PlayerSlot] = []
var simulated_joins_count: int = 0
var is_host_room_open: bool = false
var _guest_name := ""

func _ready() -> void:
	_setup_mode_buttons()
	_setup_host_view()
	_setup_join_view()
	show_view("mode")

func show_view(view_name: String) -> void:
	mode_select_view.visible = (view_name == "mode")
	host_view.visible = (view_name == "host")
	join_view.visible = (view_name == "join")

# ----------------- Mode Selection -----------------
func _setup_mode_buttons() -> void:
	btn_choose_host.pressed.connect(func() -> void:
		is_host_room_open = true
		show_view("host")
		_reset_host_lobby()
	)
	btn_choose_join.pressed.connect(func() -> void:
		show_view("join")
		join_status_label.text = ""
	)
	btn_back_to_main.pressed.connect(func() -> void:
		is_host_room_open = false
		back_to_main_requested.emit()
	)

# ----------------- Host View -----------------
func _setup_host_view() -> void:
	room_code_display.text = SIMULATED_ROOM_CODE
	btn_copy_code.pressed.connect(_on_copy_code_pressed)
	
	host_player_count.clear()
	for count in [2, 3, 4]:
		host_player_count.add_item(tr("LOBBY_PLAYERS_COUNT").format({"count": count}), count)
	host_player_count.select(2) # Default 4
	host_player_count.item_selected.connect(func(_idx: int) -> void: _refresh_host_slots())
	
	btn_simulate_player.pressed.connect(_on_simulate_remote_player_connected)
	btn_host_back.pressed.connect(func() -> void:
		is_host_room_open = false
		show_view("mode")
	)
	btn_host_start.pressed.connect(_on_host_start_pressed)

func _reset_host_lobby() -> void:
	simulated_joins_count = 0
	
	for child in host_slots_container.get_children():
		child.queue_free()
	host_slot_instances.clear()
	
	for i in range(4):
		var slot: PlayerSlot = PlayerSlotScene.instantiate()
		host_slots_container.add_child(slot)
		if i == 0:
			# The host can only edit their own name and faction.
			slot.configure(0, "", DEFAULT_COLORS[0], "MULTI_HOST_NAME")
			slot.set_role_tag("SLOT_HOST", true)
			slot.set_editable(true)
		else:
			# Other seats wait for remote connections and cannot be edited by the host.
			slot.configure(i, "", DEFAULT_COLORS[i])
			slot.set_waiting_state()
		host_slot_instances.append(slot)
	
	btn_simulate_player.disabled = false
	_refresh_host_slots()

func _refresh_host_slots() -> void:
	var total_count: int = host_player_count.get_selected_id()
	var connected_count: int = 1 # Slot 0 (Host)
	
	for i in range(host_slot_instances.size()):
		var slot := host_slot_instances[i]
		slot.visible = (i < total_count)
		if i > 0 and slot.visible and not slot.is_waiting_connection:
			connected_count += 1
	
	host_status_label.text = tr("MULTI_WAITING") % [connected_count, total_count]

func _on_simulate_remote_player_connected() -> void:
	var total_capacity := host_player_count.get_selected_id()
	
	# Find the next waiting seat within the room capacity.
	var next_slot: PlayerSlot = null
	for i in range(1, total_capacity):
		if host_slot_instances[i].is_waiting_connection:
			next_slot = host_slot_instances[i]
			break
	
	if next_slot == null:
		host_status_label.text = tr("MULTI_FULL") % [total_capacity, total_capacity]
		btn_simulate_player.disabled = true
		return
	
	var remote_name := SIMULATED_REMOTE_NAMES[simulated_joins_count % SIMULATED_REMOTE_NAMES.size()]
	var remote_faction := DEFAULT_COLORS[next_slot.slot_index % DEFAULT_COLORS.size()]
	simulated_joins_count += 1
	
	# Receive the remote player name and faction.
	next_slot.receive_remote_player(remote_name, remote_faction)
	print("[Multiplayer] Simulated remote player: '%s', seat %d, faction %d" % [remote_name, next_slot.slot_index + 1, remote_faction])
	
	_refresh_host_slots()
	
	# Check for remaining seats.
	var has_free := false
	for i in range(1, total_capacity):
		if host_slot_instances[i].is_waiting_connection:
			has_free = true
			break
	btn_simulate_player.disabled = not has_free

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(room_code_display.text)
	btn_copy_code.text = tr("MULTI_COPIED")
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if is_instance_valid(btn_copy_code):
			btn_copy_code.text = tr("MULTI_COPY")
	)
	print("[Multiplayer] Room code copied to clipboard: %s" % room_code_display.text)

func _on_host_start_pressed() -> void:
	var total_count: int = host_player_count.get_selected_id()
	print("[Multiplayer] Starting simulated room %s with capacity %d" % [room_code_display.text, total_count])
	host_started.emit({
		"code": room_code_display.text,
		"player_count": total_count
	})

# ----------------- Join View -----------------
func _setup_join_view() -> void:
	_guest_name = tr("MULTI_GUEST")
	join_name_input.text = _guest_name
	join_name_input.placeholder_text = tr("MULTI_NICKNAME")
	
	join_faction_option.clear()
	for i in range(4):
		join_faction_option.add_item(PlayerSlot.faction_label(i), i)
	join_faction_option.select(1) # Default green
	
	btn_join_back.pressed.connect(func() -> void:
		join_status_label.text = ""
		show_view("mode")
	)
	btn_connect.pressed.connect(_on_connect_pressed)

func _on_connect_pressed() -> void:
	var code := join_code_input.text.strip_edges()
	var player_name := join_name_input.text.strip_edges()
	
	if player_name.is_empty():
		_show_join_error(tr("MULTI_NAME_REQUIRED"))
		return
	if code.is_empty():
		_show_join_error(tr("MULTI_CODE_REQUIRED"))
		return
	
	# Without a backend, only the locally simulated room can be found.
	if not is_host_room_open or code.to_upper() != SIMULATED_ROOM_CODE:
		_show_join_error(tr("MULTI_NOT_FOUND") % code)
		print("[Multiplayer] Room '%s' was not found. Backend unavailable." % code)
		return
	
	# Simulate success only for the locally open host room.
	join_status_label.text = tr("MULTI_CONNECTED") % code
	join_status_label.set("theme_override_colors/font_color", Color(0.4, 0.95, 0.55, 1.0))
	print("[Multiplayer] Simulated connection to room %s for %s" % [code, player_name])
	
	join_requested.emit(code, {
		"name": player_name,
		"faction_id": join_faction_option.get_selected_id()
	})

func _show_join_error(message: String) -> void:
	join_status_label.text = message
	join_status_label.set("theme_override_colors/font_color", Color(1.0, 0.4, 0.45, 1.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for index in range(host_player_count.item_count):
			host_player_count.set_item_text(index, tr("LOBBY_PLAYERS_COUNT").format({"count": host_player_count.get_item_id(index)}))
		for index in range(join_faction_option.item_count):
			join_faction_option.set_item_text(index, PlayerSlot.faction_label(index))
		join_name_input.placeholder_text = tr("MULTI_NICKNAME")
		if join_name_input.text == _guest_name:
			_guest_name = tr("MULTI_GUEST")
			join_name_input.text = _guest_name
		btn_copy_code.text = tr("MULTI_COPY")
		join_status_label.text = ""
		_refresh_host_slots()
