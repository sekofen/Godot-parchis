# Protocolo cliente <-> servidor

Transporte: **WebSocket**, un mensaje de texto = un objeto JSON con campo `type`.
En Godot se usa `WebSocketPeer` (funciona igual en escritorio y en la exportacion web).
Limite por mensaje: 4 KB. `GET /health` responde `ok` (para comprobar el despliegue).

El servidor es la unica autoridad: tira los dados, valida turnos y aplica las
reglas (`rules.py` es un puerto de `ParquesRules.gd`). El cliente solo envia
acciones y dibuja lo que recibe.

## Sesion

Al conectar llega `welcome` con un `token`. Guardalo: si se corta la conexion
(el servidor espera 60 s por defecto) se reanuda la sesion y el asiento.

| Cliente -> servidor | Notas |
|---|---|
| `{"type":"resume","token":"..."}` | Tras reconectar. Responde `welcome` con `"resumed":true`, `room_state` y `game_state`. Error `bad_token` si expiro. |
| `{"type":"ping","t":123}` | Responde `{"type":"pong","t":123}`. |

## Salas (lobby)

| Cliente -> servidor | Respuesta |
|---|---|
| `{"type":"list_rooms"}` | `room_list` con salas abiertas (`code`, `host_name`, `players`, `max_players`) |
| `{"type":"create_room","name":"Ana","color":0,"max_players":4}` | `room_state` |
| `{"type":"join_room","code":"MEX2K","name":"Beto","color":2}` | `room_state` a todos. `color` es opcional (se asigna uno libre). |
| `{"type":"set_color","color":1}` | `room_state` a todos |
| `{"type":"start_game"}` | Solo anfitrion, minimo 2 jugadores. `room_state` + `game_state` (`event.type="started"`) |
| `{"type":"leave_room"}` | `left_room` |
| `{"type":"back_to_lobby"}` | Solo anfitrion, con la partida terminada |

Colores = ids de faccion del juego: 0 rojo, 1 verde, 2 azul, 3 amarillo.

### `room_state`
```json
{"type":"room_state",
 "room":{"code":"MEX2K","status":"lobby|playing|finished","host_id":"a1b2c3d4","max_players":4,
         "members":[{"player_id":"a1b2c3d4","name":"Ana","color":0,"connected":true,
                     "abandoned":false,"seat":null}]},
 "you":{"player_id":"a1b2c3d4","seat":null}}
```
`seat` es el indice del jugador dentro de `game_state.state.players` (solo en partida).

## Partida

Solo acepta acciones el jugador al que le toca (`state.current_player == you.seat`);
si no, `error` con `not_your_turn`.

| Cliente -> servidor | Cuando |
|---|---|
| `{"type":"roll"}` | fase `opening` o `await_roll`. **El servidor tira los dados.** |
| `{"type":"move","pawn":0,"mask":1}` | fase `move`; `pawn`/`mask` deben salir de `legal_moves`. `mask`: 1 = dado 1, 2 = dado 2, 3 = ambos (o liberar ficha con pares) |
| `{"type":"bonus","pawn":2}` | fase `bonus` (tercer par seguido) |

### `game_state` (se envia a todos tras cada accion)
```json
{"type":"game_state",
 "state":{"players":[{"name":"Ana","color":0}],"pawns":[[-1,-1,0,5]],
          "current_player":0,"phase":"move","winner":-1,"last_roll":[3,5],
          "dice_remaining":[true,true],"consecutive_doubles":0,"jail_attempts":3,
          "notice":"...","captured":[{"player":1,"pawn":2}],
          "legal_moves":[{"pawn":2,"mask":3,"steps":8,"target":13,"kind":"move"}]},
 "event":{"type":"rolled|moved|bonus|started","seat":0,"auto":false, "...":"..."}}
```
- `pawns[seat][i]`: -1 carcel, 0 salida, 89 (`GOAL`) llegada. Mismos valores que `ParquesRules.gd`.
- `event` sirve para animar: `rolled{dice}` (el cliente anima los dados para que
  caigan en esos valores), `moved{pawn,mask,from,to,captured}`, `bonus{pawn}`.
  `auto:true` = jugada hecha por el servidor por un jugador ausente.
- Fin: `state.phase == "game_over"` y `state.winner`.

## Errores
`{"type":"error","code":"...","message":"..."}`. Codigos: `bad_request`, `bad_token`,
`bad_name`, `bad_color`, `color_taken`, `room_not_found`, `room_full`,
`game_in_progress`, `already_in_room`, `not_in_room`, `not_host`,
`not_enough_players`, `not_your_turn`, `wrong_phase`, `illegal_move`.

## Desconexiones
- Desconexion: el miembro queda `connected:false` y tiene 60 s (`--grace`) para `resume`.
- Pasado ese tiempo, o si sale con `leave_room` en plena partida, queda
  `abandoned:true` y **el servidor juega por el** (tira y mueve al azar) para no
  bloquear a los demas. Si todos abandonan, la sala se cierra.
- En el lobby, quien se va sale de la sala; si era el anfitrion, pasa al siguiente.
