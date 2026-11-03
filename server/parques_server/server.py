"""Transporte WebSocket (compatible con WebSocketPeer de Godot, incluido web)."""
from __future__ import annotations

import asyncio
import json
import logging
from http import HTTPStatus

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from .rooms import Member, RoomManager

log = logging.getLogger("parques")

MAX_MESSAGE_BYTES = 4096
OUTBOX_LIMIT = 200


class WsClient:
    """Cola de salida por conexion: los handlers son sincronos y el orden de
    los mensajes se conserva."""

    def __init__(self, ws: ServerConnection) -> None:
        self.ws = ws
        self.member: Member | None = None
        self.outbox: asyncio.Queue[str | None] = asyncio.Queue()
        self.writer = asyncio.create_task(self._write_loop())

    def send(self, message: dict) -> None:
        if self.outbox.qsize() >= OUTBOX_LIMIT:
            self.close()
            return
        self.outbox.put_nowait(json.dumps(message, separators=(",", ":")))

    def close(self) -> None:
        asyncio.create_task(self.ws.close())

    async def _write_loop(self) -> None:
        try:
            while (data := await self.outbox.get()) is not None:
                await self.ws.send(data)
        except ConnectionClosed:
            pass

    async def shutdown(self) -> None:
        self.outbox.put_nowait(None)
        await self.writer


def make_handler(manager: RoomManager):
    async def handler(ws: ServerConnection) -> None:
        client = WsClient(ws)
        client.member = manager.connect(client)
        try:
            async for raw in ws:
                if isinstance(raw, bytes):
                    client.send({"type": "error", "code": "bad_request", "message": "Usa texto JSON."})
                    continue
                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    client.send({"type": "error", "code": "bad_request", "message": "JSON invalido."})
                    continue
                manager.handle(client.member, message)
        except ConnectionClosed:
            pass
        finally:
            manager.disconnect(client.member, client)
            await client.shutdown()

    return handler


def _process_request(connection: ServerConnection, request):
    """GET /health para comprobar el despliegue sin abrir un WebSocket."""
    if request.path == "/health":
        return connection.respond(HTTPStatus.OK, "ok\n")
    return None


async def run(host: str, port: int, manager: RoomManager) -> None:
    async with serve(
        make_handler(manager),
        host,
        port,
        max_size=MAX_MESSAGE_BYTES,
        process_request=_process_request,
    ) as server:
        log.info("Servidor de Parques escuchando en ws://%s:%d", host, port)
        await server.serve_forever()
