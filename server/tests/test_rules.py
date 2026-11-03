"""Puerto de tests/unit/test_rules.gd para verificar que Python == GDScript."""
import random

from parques_server.rules import FINISHED, GOAL, TRACK_STEPS, ParquesRules


def fresh():
    r = ParquesRules()
    assert r.configure([{"name": "Red", "color": 0}, {"name": "Blue", "color": 2}])
    assert r.roll(6, 6)
    assert r.roll(1, 2)
    assert r.phase == "await_roll" and r.current_player == 0
    return r


def test_setup_and_ties():
    r = ParquesRules()
    assert not r.configure([{"name": "A", "color": 0}, {"name": "B", "color": 0}])
    assert not r.configure([{"name": " ", "color": 0}, {"name": "B", "color": 2}])
    entries = [{"name": "A", "color": 0}, {"name": "B", "color": 2}, {"name": "C", "color": 1}]
    assert r.configure(entries)
    r.roll(6, 1); r.roll(3, 4); r.roll(1, 2)
    assert r.phase == "opening" and r.current_player == 0
    r.roll(2, 2); r.roll(5, 1)
    assert r.phase == "await_roll" and r.current_player == 1
    assert r.consecutive_doubles == 0
    assert not r.roll(0, 7)
    assert not r.configure(entries)


def test_jail_and_dice():
    r = fresh()
    r.roll(1, 2)
    assert r.current_player == 0 and r.jail_attempts == 2
    r.roll(3, 4)
    assert r.jail_attempts == 1
    r.roll(5, 6)
    assert r.current_player == 1 and r.jail_attempts == 3
    r.roll(2, 2)
    assert r.phase == "move" and len(r.legal_moves()) == 4
    assert not r.play(0, 1)
    assert r.play(0, 3)
    assert r.pawns[1][0] == 0 and r.phase == "await_roll"
    r.roll(2, 3)
    assert not r.play(1, 3)
    assert len(r.legal_moves()) == 3
    assert r.play(0, 1)
    assert r.pawns[1][0] == 2 and r.dice_remaining == [False, True]
    assert not r.play(0, 1)
    assert not r.roll(6, 6)
    assert r.play(0, 2)
    assert r.pawns[1][0] == 5 and r.current_player == 0


def test_capture_and_protection():
    r = fresh()
    r.pawns[0][0] = 0
    r.pawns[1][0] = 49
    r.roll(1, 2); r.play(0, 1)
    assert r.pawns[1][0] == -1 and len(r.captured) == 1

    safe = fresh()
    safe.pawns[0][0] = 78
    safe.pawns[1][0] = 31
    safe.roll(1, 2); safe.play(0, 1)
    assert safe.pawns[1][0] == 31 and not safe.captured

    salida = fresh()
    salida.pawns[0][0] = 71
    salida.pawns[1][0] = 24
    salida.roll(1, 2); salida.play(0, 1)
    assert salida.pawns[1][0] == 24
    assert salida.circuit_index(0, TRACK_STEPS + 1) == -1
    assert salida.circuit_index(0, TRACK_STEPS) == 11


def test_doubles_bonus_and_goal():
    r = fresh()
    r.roll(2, 2); r.play(0, 3)
    r.roll(3, 3); r.play(0, 3)
    assert r.phase == "await_roll" and r.consecutive_doubles == 2
    r.roll(4, 4)
    assert r.phase == "bonus" and not r.play(0, 3)
    assert r.claim_bonus(2) and r.pawns[0][2] == FINISHED
    assert r.phase == "await_roll" and r.consecutive_doubles == 0
    assert not r.claim_bonus(1)

    exact = fresh()
    exact.pawns[0][0] = GOAL - 2
    exact.roll(1, 2)
    assert len(exact.legal_moves()) == 2
    assert not exact.play(0, 3)
    exact.play(0, 2)
    assert exact.finished_count(0) == 1 and exact.current_player == 1

    win = fresh()
    win.pawns[0] = [GOAL, GOAL, GOAL, GOAL - 2]
    win.roll(2, 4); win.play(3, 1)
    assert win.phase == "game_over" and win.winner == 0
    assert not win.roll(1, 1) and not win.play(3, 2)


def test_turn_order_passes_right():
    r = ParquesRules()
    r.configure([{"name": n, "color": c} for c, n in enumerate("RGBY")])
    r.roll(6, 6)
    for _ in range(3):
        r.roll(1, 2)
    for color in (3, 2, 1, 0):
        for _ in range(3):
            r.roll(1, 2)
        assert r.players[r.current_player]["color"] == color


def test_random_matches_always_finish():
    rng = random.Random(158342)
    for count in (2, 3, 4):
        for _ in range(3):
            r = ParquesRules()
            r.configure([{"name": f"P{i}", "color": i} for i in range(count)])
            actions = 0
            while r.phase != "game_over" and actions < 30000:
                actions += 1
                if r.phase in ("opening", "await_roll"):
                    assert r.roll(rng.randint(1, 6), rng.randint(1, 6))
                elif r.phase == "move":
                    moves = r.legal_moves()
                    assert moves
                    m = rng.choice(moves)
                    assert r.play(m["pawn"], m["mask"])
                elif r.phase == "bonus":
                    pawn = next(p for p in range(4) if r.pawns[r.current_player][p] != FINISHED)
                    assert r.claim_bonus(pawn)
                assert all(-1 <= p <= GOAL for row in r.pawns for p in row)
            assert r.phase == "game_over"
