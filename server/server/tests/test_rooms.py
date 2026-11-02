import asyncio

from parques_server.rooms import RoomManager
from tests.conftest import new_player


def send(manager, member, **msg):
    manager.handle(member, msg)


def setup_room(manager, n=2):
    players = [new_player(manager) for _ in range(n)]
    host_c, host = players[0]
    send(manager, host, type="create_room", name="Host", color=0, max_players=4)
    code = host_c.last("room_state")["room"]["code"]
    for i, (_, m) in enumerate(players[1:], start=1):
        send(manager, m, type="join_room", code=code, name=f"P{i}", color=[0, 2, 1, 3][i])
    return code, players


def test_create_join_and_list(manager):
    code, players = setup_room(manager, 2)
    (hc, _), (jc, _) = players
    assert len(hc.last("room_state")["room"]["members"]) == 2
    assert jc.last("room_state")["room"]["code"] == code
    viewer, v = new_player(manager)
    send(manager, v, type="list_rooms")
    assert viewer.last("room_list")["rooms"][0]["code"] == code


def test_errors(manager):
    c, m = new_player(manager)
    send(manager, m, type="join_room", code="ZZZZZ", name="x")
    assert c.last("error")["code"] == "room_not_found"
    send(manager, m, type="roll")
    assert c.last("error")["code"] == "not_in_room"
    send(manager, m, type="create_room", name="  ", color=0)
    assert c.last("error")["code"] == "bad_name"
    send(manager, m, type="create_room", name="A", color=9)
    assert c.last("error")["code"] == "bad_color"
    send(manager, m, type="nope")
    assert c.last("error")["code"] == "bad_request"
    manager.handle(m, "no es dict")
    assert c.last("error")["code"] == "bad_request"


def test_color_taken_and_room_full(manager):
    code, players = setup_room(manager, 2)
    c, m = new_player(manager)
    send(manager, m, type="join_room", code=code, name="X", color=0)
    assert c.last("error")["code"] == "color_taken"
    send(manager, m, type="join_room", code=code, name="X")  # color automatico
    assert c.last("room_state")["room"]["members"][-1]["color"] in (1, 3)
    full = RoomManager()
    cc, mm = new_player(full)
    send(full, mm, type="create_room", name="A", color=0, max_players=2)
    code2 = cc.last("room_state")["room"]["code"]
    for i in (1, 2):
        c2, m2 = new_player(full)
        send(full, m2, type="join_room", code=code2, name=f"B{i}", color=i)
    assert c2.last("error")["code"] == "room_full"


def test_only_host_starts_and_needs_two(manager):
    c, host = new_player(manager)
    send(manager, host, type="create_room", name="H", color=0)
    send(manager, host, type="start_game")
    assert c.last("error")["code"] == "not_enough_players"
    code = c.last("room_state")["room"]["code"]
    jc, joiner = new_player(manager)
    send(manager, joiner, type="join_room", code=code, name="J", color=2)
    send(manager, joiner, type="start_game")
    assert jc.last("error")["code"] == "not_host"
    send(manager, host, type="start_game")
    assert c.last("game_state")["event"]["type"] == "started"
    assert c.last("room_state")["room"]["status"] == "playing"
    # ya no aparece en la lista ni se puede entrar
    xc, x = new_player(manager)
    send(manager, x, type="join_room", code=code, name="X")
    assert xc.last("error")["code"] == "game_in_progress"


def test_turn_enforcement_and_server_rolls(manager):
    code, players = setup_room(manager, 2)
    (hc, host), (jc, joiner) = players
    send(manager, host, type="start_game")
    state = hc.last("game_state")["state"]
    first = state["current_player"]
    seat_member = {0: host, 1: joiner}
    other = seat_member[1 - first]
    other_c = hc if other is host else jc
    send(manager, other, type="roll")
    assert other_c.last("error")["code"] == "not_your_turn"
    send(manager, seat_member[first], type="roll")
    ev = hc.last("game_state")["event"]
    assert ev["type"] == "rolled" and all(1 <= d <= 6 for d in ev["dice"])
    # ambos reciben el mismo estado
    assert hc.last("game_state") == jc.last("game_state")


def play_to_end(manager, members_by_seat, room):
    steps = 0
    while room.rules.phase != "game_over" and steps < 40000:
        steps += 1
        seat = room.rules.current_player
        m = members_by_seat[seat]
        ph = room.rules.phase
        if ph in ("opening", "await_roll"):
            send(manager, m, type="roll")
        elif ph == "move":
            mv = manager.rng.choice(room.rules.legal_moves())
            send(manager, m, type="move", pawn=mv["pawn"], mask=mv["mask"])
        elif ph == "bonus":
            pawn = next(p for p in range(4) if room.rules.pawns[seat][p] != 89)
            send(manager, m, type="bonus", pawn=pawn)
    return steps


def test_full_game_through_manager(manager):
    code, players = setup_room(manager, 3)
    members = [m for _, m in players]
    send(manager, members[0], type="start_game")
    room = manager.rooms[code]
    play_to_end(manager, room.seats, room)
    assert room.rules.phase == "game_over" and room.status == "finished"
    # Volver al lobby
    send(manager, members[1], type="back_to_lobby")
    assert players[1][0].last("error")["code"] == "not_host"
    send(manager, members[0], type="back_to_lobby")
    assert room.status == "lobby" and room.rules is None


async def test_disconnect_resume_within_grace():
    mgr = RoomManager(grace_seconds=5, autoplay_delay=0)
    code, players = setup_room(mgr, 2)
    (hc, host), (jc, joiner) = players
    send(mgr, host, type="start_game")
    mgr.disconnect(joiner, jc)
    assert hc.last("room_state")["room"]["members"][1]["connected"] is False
    nc, temp = new_player(mgr)
    nc.member = temp
    mgr.handle(temp, {"type": "resume", "token": joiner.token})
    assert nc.member is joiner
    assert nc.last("welcome")["resumed"] is True
    assert nc.last("game_state") is not None  # recibe el estado actual
    assert hc.last("room_state")["room"]["members"][1]["connected"] is True


async def test_grace_expiry_triggers_autoplay_and_finishes_game():
    mgr = RoomManager(grace_seconds=0.01, autoplay_delay=0.0)
    code, players = setup_room(mgr, 2)
    (hc, host), (jc, joiner) = players
    send(mgr, host, type="start_game")
    room = mgr.rooms[code]
    # El anfitrion sigue jugando; el otro se va y el servidor juega por el.
    mgr.disconnect(joiner, jc)
    await asyncio.sleep(0.05)
    assert joiner.abandoned
    for _ in range(30000):
        await asyncio.sleep(0)
        if room.rules.phase == "game_over":
            break
        seat = room.rules.current_player
        if room.seats[seat] is host:
            ph = room.rules.phase
            if ph in ("opening", "await_roll"):
                send(mgr, host, type="roll")
            elif ph == "move":
                mv = mgr.rng.choice(room.rules.legal_moves())
                send(mgr, host, type="move", pawn=mv["pawn"], mask=mv["mask"])
            elif ph == "bonus":
                pawn = next(p for p in range(4) if room.rules.pawns[seat][p] != 89)
                send(mgr, host, type="bonus", pawn=pawn)
    assert room.rules.phase == "game_over"


def test_lobby_leave_transfers_host_and_closes_empty(manager):
    code, players = setup_room(manager, 2)
    (hc, host), (jc, joiner) = players
    send(manager, host, type="leave_room")
    assert hc.last("left_room")
    assert jc.last("room_state")["room"]["host_id"] == joiner.player_id
    send(manager, joiner, type="leave_room")
    assert code not in manager.rooms
