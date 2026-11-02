# Servidor de partidas — Parques

Servidor ligero en Python (asyncio + `websockets`) que gestiona salas y
mantiene la logica de la partida de forma centralizada. Los clientes de Godot
solo envian acciones y muestran el estado.

```sh
pip install -r requirements.txt
python3 -m parques_server --port 8765        # ws://localhost:8765
python3 -m parques_server --help             # --grace, --autoplay-delay, -v

pip install -r requirements-dev.txt
python3 -m pytest                            # 17 pruebas
```

- Protocolo: [PROTOCOL.md](PROTOCOL.md)
- `parques_server/rules.py`: puerto de `ParquesRules.gd` (mismas reglas y tests).
  Si cambian las reglas en GDScript, hay que reflejarlo aqui.
- `parques_server/rooms.py`: salas, turnos, reconexion, autoplay (sin red).
- `parques_server/server.py`: transporte WebSocket.

Para publicarlo en internet con `wss://` (necesario si el juego web se sirve por
HTTPS) basta un proxy inverso (Caddy/nginx) delante del puerto 8765.
