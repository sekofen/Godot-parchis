"""Prueba extremo a extremo con WebSockets reales (lo que usara Godot)."""
import asyncio
import json
import random

import pytest
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve

from parques_server.rooms import RoomManager
from parques_server.server import _process_request, make_handler


@pytest.fixture
async def url():
    manager = RoomManager(grace_seconds=5, autoplay_delay=0, rng=random.Random(3))
    async with serve(make_handler(manager), "127.0.0.1", 0, max_size=4096,
                     process_request=_process_request) as server:
        port = server.sockets[0].getsockname()[1]
        yield f"ws://127.0.0.1:{port}"


async def recv_until(ws, type_, timeout=2):
    async def loop():
        while True:
            msg = json.loads(await ws.recv())
            if msg["type"] == type_:
                return msg
    return await asyncio.wait_for(loop(), timeout)


async def test_resume_keeps_seat(url):
    a = await connect(url)
    wa = await recv_until(a, "welcome")
    b = await connect(url)
    await recv_until(b, "welcome")
    await a.send(json.dumps({"type": "create_room", "name": "Ana", "color": 0}))
    code = (await recv_until(a, "room_state"))["room"]["code"]
    await b.send(json.dumps({"type": "join_room", "code": code, "name": "Beto", "color": 2}))
    await a.send(json.dumps({"type": "start_game"}))
    await recv_until(a, "game_state")
    await a.close()
    await asyncio.sleep(0.1)
    a2 = await connect(url)
    await recv_until(a2, "welcome")
    await a2.send(json.dumps({"type": "resume", "token": wa["token"]}))
    back = await recv_until(a2, "welcome")
    assert back["resumed"] and back["player_id"] == wa["player_id"]
    gs = await recv_until(a2, "game_state")
    assert gs["state"]["phase"] == "opening"
    await a2.close(); await b.close()


async def test_health_and_bad_input(url):
    import urllib.request
    host = url.replace("ws://", "http://")
    body = await asyncio.to_thread(lambda: urllib.request.urlopen(host + "/health").read())
    assert body == b"ok\n"
    async with connect(url) as ws:
        await recv_until(ws, "welcome")
        await ws.send("{no json")
        assert (await recv_until(ws, "error"))["code"] == "bad_request"
        await ws.send(json.dumps({"type": "list_rooms"}))
        assert (await recv_until(ws, "room_list"))["rooms"] == []
