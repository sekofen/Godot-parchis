extends Node
class_name NetworkManagerClass
## Gestor centralizado de red y comunicación con el backend (WebSockets).
## Todas las intenciones de juego (dados, movimientos, salas) pasan por aquí.

signal connection_established()
signal connection_lost()
signal connection_error(message: String)

# Eventos de sala y lobby
signal room_created(room_code: String)
signal room_joined(room_code: String, players: Array)
signal player_joined(player_data: Dictionary)
signal player_left(player_id: int)

# Eventos de partida emitidos por el servidor
signal dice_roll_broadcast(player_id: int, values: Array[int], seed_val: int)
signal move_broadcast(player_id: int, move_data: Dictionary)
signal turn_changed(new_player_id: int)
signal game_state_synced(state: Dictionary)

const DEFAULT_SERVER_URL := "ws://127.0.0.1:8000/ws"

var socket := WebSocketPeer.new()
var is_connected_to_server := false
var current_room_code := ""
var local_player_id := -1

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected_to_server:
				is_connected_to_server = true
				connection_established.emit()
				print("[NetworkManager] Conectado al servidor.")
			
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				var text := packet.get_string_from_utf8()
				_handle_raw_message(text)
				
		WebSocketPeer.STATE_CLOSED:
			if is_connected_to_server:
				is_connected_to_server = false
				connection_lost.emit()
				print("[NetworkManager] Conexión cerrada.")
				
		WebSocketPeer.STATE_CLOSING:
			pass
			
		WebSocketPeer.STATE_CONNECTING:
			pass

## Inicia la conexión con el servidor backend
func connect_to_server(url: String = DEFAULT_SERVER_URL) -> void:
	if is_connected_to_server:
		return
	print("[NetworkManager] Conectando a %s..." % url)
	var err := socket.connect_to_url(url)
	if err != OK:
		connection_error.emit("No se pudo iniciar la conexión: error %d" % err)

## Cierra la conexión
func disconnect_from_server() -> void:
	if is_connected_to_server:
		socket.close()
		is_connected_to_server = false

# -------------------------------------------------------------
# ENVÍO DE ACCIONES AL SERVIDOR (Intenciones del jugador)
# -------------------------------------------------------------

## Pide al servidor crear una nueva sala
func request_create_room(player_name: String, faction_id: int, max_players: int = 4) -> void:
	_send("CREATE_ROOM", {
		"name": player_name,
		"faction": faction_id,
		"capacity": max_players
	})

## Pide unirse a una sala existente mediante código
func request_join_room(code: String, player_name: String, faction_id: int) -> void:
	_send("JOIN_ROOM", {
		"room_code": code,
		"name": player_name,
		"faction": faction_id
	})

## Solicita al servidor lanzar los dados (El servidor calcula y responde a todos)
func request_roll_dice() -> void:
	_send("REQUEST_ROLL", {
		"room_code": current_room_code
	})

## Solicita al servidor ejecutar un movimiento de ficha
func request_move(pawn_index: int, target_progress: int, die_used: int, kind: String) -> void:
	_send("REQUEST_MOVE", {
		"room_code": current_room_code,
		"pawn": pawn_index,
		"target": target_progress,
		"die": die_used,
		"kind": kind
	})

# -------------------------------------------------------------
# INTERPRETACIÓN DE MENSAJES RECIBIDOS DESDE EL SERVIDOR
# -------------------------------------------------------------

func _send(action_type: String, payload: Dictionary) -> void:
	if not is_connected_to_server:
		push_warning("[NetworkManager] Intento de envío sin conexión activa.")
		return
	var message := {
		"action": action_type,
		"payload": payload
	}
	socket.send_text(JSON.stringify(message))

func _handle_raw_message(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	
	var event: String = parsed.get("event", "")
	var data: Dictionary = parsed.get("data", {})
	
	match event:
		"ROOM_CREATED":
			current_room_code = data.get("room_code", "")
			local_player_id = data.get("player_id", 0)
			room_created.emit(current_room_code)
			
		"ROOM_JOINED":
			current_room_code = data.get("room_code", "")
			local_player_id = data.get("player_id", -1)
			var player_list: Array = data.get("players", [])
			room_joined.emit(current_room_code, player_list)
			
		"PLAYER_CONNECTED":
			player_joined.emit(data)
			
		"PLAYER_DISCONNECTED":
			player_left.emit(data.get("player_id", -1))
			
		"DICE_ROLLED":
			# El servidor envía: {"player_id": 0, "values": [4, 6], "seed": 91823}
			var p_id: int = data.get("player_id", 0)
			var vals_array: Array = data.get("values", [1, 1])
			var values: Array[int] = [int(vals_array[0]), int(vals_array[1])]
			var seed_val: int = int(data.get("seed", -1))
			dice_roll_broadcast.emit(p_id, values, seed_val)
			
		"MOVE_EXECUTED":
			var p_id: int = data.get("player_id", 0)
			var move_data: Dictionary = data.get("move", {})
			move_broadcast.emit(p_id, move_data)
			
		"TURN_CHANGED":
			turn_changed.emit(data.get("current_player", 0))
			
		"ERROR":
			connection_error.emit(data.get("message", "Error desconocido del servidor"))

