"""Logica de salas y partidas, independiente del transporte.

El servidor es la unica autoridad: valida turnos, tira los dados y aplica las
reglas. Los clientes solo envian acciones y dibujan el estado recibido.
"""
from __future__ import annotations

import asyncio
import logging
import random
import secrets
import time
from dataclasses import dataclass, field
from typing import Any, Optional, Protocol

from .rules import FINISHED, ParquesRules

log = logging.getLogger("parques")

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # sin 0/O/1/I
CODE_LENGTH = 5
MAX_NAME = 20


class Client(Protocol):
    """Lo unico que el manager necesita del transporte."""

    def send(self, message: dict) -> None: ...
    def close(self) -> None: ...


class GameError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(eq=False)
class Member:
    player_id: str
    token: str
    client: Optional[Client] = None
    name: str = ""
    color: int = -1
    room: Optional["Room"] = None
    connected: bool = True
    abandoned: bool = False  # abandono la partida: el servidor juega por el
    grace_handle: Optional[asyncio.TimerHandle] = None

    def send(self, message: dict) -> None:
        if self.client is not None and self.connected:
            self.client.send(message)


@dataclass(eq=False)
class Room:
    code: str
    host_id: str
    max_players: int
    members: list[Member] = field(default_factory=list)
    status: str = "lobby"  # lobby | playing | finished
    rules: Optional[ParquesRules] = None
    seats: list[Member] = field(default_factory=list)  # asiento -> miembro
    created_at: float = field(default_factory=time.time)
    autoplay_handle: Optional[asyncio.TimerHandle] = None

    def alive_members(self) -> list[Member]:
        return [m for m in self.members if not m.abandoned]


class RoomManager:
    def __init__(
        self,
        grace_seconds: float = 60.0,
        autoplay_delay: float = 1.2,
        rng: Optional[random.Random] = None,
    ) -> None:
        self.grace_seconds = grace_seconds
        self.autoplay_delay = autoplay_delay
        self.rng = rng or random.Random()
        self.rooms: dict[str, Room] = {}
        self.sessions: dict[str, Member] = {}  # token -> miembro

    # ============================================================ sesiones
    def connect(self, client: Client) -> Member:
        member = Member(player_id=secrets.token_hex(4), token=secrets.token_urlsafe(16), client=client)
        self.sessions[member.token] = member
        member.send({"type": "welcome", "player_id": member.player_id, "token": member.token})
        return member

    def disconnect(self, member: Member, client: Client) -> None:
        # Si ya se reanudo con otra conexion, la vieja no cuenta.
        if member.client is not client:
            return
        member.connected = False
        member.client = None
        if member.room is None:
            self.sessions.pop(member.token, None)
            return
        log.info("%s se desconecto de %s (gracia %.0fs)", member.name, member.room.code, self.grace_seconds)
        self._broadcast_room(member.room)
        loop = asyncio.get_running_loop()
        member.grace_handle = loop.call_later(self.grace_seconds, self._grace_expired, member)

    def _grace_expired(self, member: Member) -> None:
        member.grace_handle = None
        if member.connected:
            return
        log.info("%s no volvio: se retira", member.name)
        self._remove_member(member)

    def handle(self, member: Member, message: Any) -> None:
        """Punto de entrada: cualquier error de reglas se devuelve como `error`."""
        try:
            if not isinstance(message, dict) or not isinstance(message.get("type"), str):
                raise GameError("bad_request", "Mensaje invalido.")
            handler = getattr(self, f"_on_{message['type']}", None)
            if handler is None:
                raise GameError("bad_request", f"Tipo desconocido: {message['type']}")
            handler(member, message)
        except GameError as err:
            member.send({"type": "error", "code": err.code, "message": err.message})

    # ============================================================ mensajes
    def _on_ping(self, member: Member, msg: dict) -> None:
        member.send({"type": "pong", "t": msg.get("t")})

    def _on_resume(self, member: Member, msg: dict) -> None:
        """Reanuda una sesion previa con su token (tras perder la conexion)."""
        old = self.sessions.get(str(msg.get("token", "")))
        if old is None or old is member:
            raise GameError("bad_token", "Sesion no encontrada o expirada.")
        if old.client is not None:
            old.client.close()
        client = member.client
        self.sessions.pop(member.token, None)  # la sesion temporal ya no sirve
        old.client = client
        old.connected = True
        if old.grace_handle:
            old.grace_handle.cancel()
            old.grace_handle = None
        # El cliente queda ligado a la sesion antigua: el manager lo conoce por `old`.
        if hasattr(client, "member"):
            client.member = old
        old.send({"type": "welcome", "player_id": old.player_id, "token": old.token, "resumed": True})
        if old.room:
            self._broadcast_room(old.room)
            if old.room.rules is not None:
                old.send(self._game_message(old.room, None))

    def _on_list_rooms(self, member: Member, msg: dict) -> None:
        rooms = [
            {
                "code": r.code,
                "host_name": self._member(r, r.host_id).name,
                "players": len(r.members),
                "max_players": r.max_players,
            }
            for r in self.rooms.values()
            if r.status == "lobby" and len(r.members) < r.max_players
        ]
        member.send({"type": "room_list", "rooms": rooms})

    def _on_create_room(self, member: Member, msg: dict) -> None:
        self._require_no_room(member)
        name = self._clean_name(msg.get("name"))
        color = self._clean_color(msg.get("color", 0))
        max_players = msg.get("max_players", 4)
        if not isinstance(max_players, int) or isinstance(max_players, bool) or not 2 <= max_players <= 4:
            raise GameError("bad_request", "max_players debe estar entre 2 y 4.")
        room = Room(code=self._new_code(), host_id=member.player_id, max_players=max_players)
        self.rooms[room.code] = room
        member.name, member.color, member.room = name, color, room
        room.members.append(member)
        log.info("Sala %s creada por %s", room.code, name)
        self._broadcast_room(room)

    def _on_join_room(self, member: Member, msg: dict) -> None:
        self._require_no_room(member)
        room = self.rooms.get(str(msg.get("code", "")).strip().upper())
        if room is None:
            raise GameError("room_not_found", "No existe una sala con ese codigo.")
        if room.status != "lobby":
            raise GameError("game_in_progress", "La partida ya empezo.")
        if len(room.members) >= room.max_players:
            raise GameError("room_full", "La sala esta llena.")
        name = self._clean_name(msg.get("name"))
        taken = {m.color for m in room.members}
        color = msg.get("color")
        if color is None:
            color = next(c for c in range(4) if c not in taken)
        color = self._clean_color(color)
        if color in taken:
            raise GameError("color_taken", "Ese color ya esta ocupado.")
        member.name, member.color, member.room = name, color, room
        room.members.append(member)
        self._broadcast_room(room)

    def _on_set_color(self, member: Member, msg: dict) -> None:
        room = self._require_room(member, "lobby")
        color = self._clean_color(msg.get("color"))
        if any(m.color == color for m in room.members if m is not member):
            raise GameError("color_taken", "Ese color ya esta ocupado.")
        member.color = color
        self._broadcast_room(room)

    def _on_set_name(self, member: Member, msg: dict) -> None:
        room = self._require_room(member, "lobby")
        name = self._clean_name(msg.get("name"))
        member.name = name
        self._broadcast_room(room)

    def _on_leave_room(self, member: Member, msg: dict) -> None:
        self._require_room(member)
        self._remove_member(member)
        member.send({"type": "left_room"})

    def _on_start_game(self, member: Member, msg: dict) -> None:
        room = self._require_room(member, "lobby")
        if room.host_id != member.player_id:
            raise GameError("not_host", "Solo el anfitrion puede iniciar.")
        if len(room.members) < 2:
            raise GameError("not_enough_players", "Hacen falta al menos 2 jugadores.")
        rules = ParquesRules()
        entries = [{"name": m.name, "color": m.color} for m in room.members]
        if not rules.configure(entries):
            raise GameError("bad_setup", "Configuracion invalida (nombres o colores).")
        room.rules = rules
        room.seats = list(room.members)
        room.status = "playing"
        log.info("Sala %s inicia con %d jugadores", room.code, len(room.members))
        self._broadcast_room(room)
        self._broadcast_game(room, {"type": "started"})
        self._schedule_autoplay(room)

    def _on_roll(self, member: Member, msg: dict) -> None:
        room, seat = self._require_turn(member)
        rules = room.rules
        if rules.phase not in ("opening", "await_roll"):
            raise GameError("wrong_phase", "Ahora no se puede tirar.")
        a, b = self.rng.randint(1, 6), self.rng.randint(1, 6)
        self._do_roll(room, seat, a, b)

    def _on_move(self, member: Member, msg: dict) -> None:
        room, seat = self._require_turn(member)
        pawn, mask = msg.get("pawn"), msg.get("mask")
        if not all(isinstance(v, int) and not isinstance(v, bool) for v in (pawn, mask)):
            raise GameError("bad_request", "pawn y mask deben ser enteros.")
        self._do_move(room, seat, pawn, mask)

    def _on_bonus(self, member: Member, msg: dict) -> None:
        room, seat = self._require_turn(member)
        pawn = msg.get("pawn")
        if not isinstance(pawn, int) or isinstance(pawn, bool):
            raise GameError("bad_request", "pawn debe ser entero.")
        self._do_bonus(room, seat, pawn)

    def _on_back_to_lobby(self, member: Member, msg: dict) -> None:
        room = self._require_room(member)
        if room.host_id != member.player_id:
            raise GameError("not_host", "Solo el anfitrion puede reiniciar la sala.")
        if room.status == "lobby":
            return
        if room.rules is None or room.rules.phase != "game_over":
            raise GameError("wrong_phase", "La partida no ha terminado.")
        self._reset_to_lobby(room)

    # ============================================================ acciones de juego
    def _do_roll(self, room: Room, seat: int, a: int, b: int, auto: bool = False) -> None:
        if not room.rules.roll(a, b):
            raise GameError("wrong_phase", "Tirada rechazada.")
        self._after_action(room, {"type": "rolled", "seat": seat, "dice": [a, b], "auto": auto})

    def _do_move(self, room: Room, seat: int, pawn: int, mask: int, auto: bool = False) -> None:
        rules = room.rules
        if rules.phase != "move":
            raise GameError("wrong_phase", "Ahora no se puede mover.")
        before = rules.pawns[seat][pawn] if 0 <= pawn < 4 else None
        if not rules.play(pawn, mask):
            raise GameError("illegal_move", "Movimiento ilegal.")
        self._after_action(
            room,
            {
                "type": "moved",
                "seat": seat,
                "pawn": pawn,
                "mask": mask,
                "from": before,
                "to": rules.pawns[seat][pawn],
                "captured": [dict(c) for c in rules.captured],
                "auto": auto,
            },
        )

    def _do_bonus(self, room: Room, seat: int, pawn: int, auto: bool = False) -> None:
        if room.rules.phase != "bonus":
            raise GameError("wrong_phase", "No hay bonus disponible.")
        if not room.rules.claim_bonus(pawn):
            raise GameError("illegal_move", "Ficha invalida para el bonus.")
        self._after_action(room, {"type": "bonus", "seat": seat, "pawn": pawn, "auto": auto})

    def _after_action(self, room: Room, event: dict) -> None:
        if room.rules.phase == "game_over":
            room.status = "finished"
            self._broadcast_room(room)
        self._broadcast_game(room, event)
        self._schedule_autoplay(room)

    # ============================================================ autoplay
    def _schedule_autoplay(self, room: Room) -> None:
        """Si le toca a alguien que abandono, el servidor juega por el."""
        if room.autoplay_handle is not None or room.status != "playing":
            return
        seat = room.rules.current_player
        if not room.seats[seat].abandoned:
            return
        loop = asyncio.get_running_loop()
        room.autoplay_handle = loop.call_later(self.autoplay_delay, self._autoplay_step, room)

    def _autoplay_step(self, room: Room) -> None:
        room.autoplay_handle = None
        if room.status != "playing" or room.code not in self.rooms:
            return
        rules = room.rules
        seat = rules.current_player
        if not room.seats[seat].abandoned:
            return
        try:
            if rules.phase in ("opening", "await_roll"):
                self._do_roll(room, seat, self.rng.randint(1, 6), self.rng.randint(1, 6), auto=True)
            elif rules.phase == "move":
                moves = rules.legal_moves()
                releases = [m for m in moves if m["kind"] == "release"]
                choice = self.rng.choice(releases or moves)
                self._do_move(room, seat, choice["pawn"], choice["mask"], auto=True)
            elif rules.phase == "bonus":
                pawn = next(p for p in range(4) if rules.pawns[seat][p] != FINISHED)
                self._do_bonus(room, seat, pawn, auto=True)
        except GameError:  # pragma: no cover - defensivo
            log.exception("Fallo el autoplay en %s", room.code)

    # ============================================================ salida de miembros
    def _remove_member(self, member: Member) -> None:
        """Salida voluntaria o gracia vencida."""
        room = member.room
        if member.grace_handle:
            member.grace_handle.cancel()
            member.grace_handle = None
        if room is None:
            return
        if not member.connected:
            self.sessions.pop(member.token, None)
        if room.status == "lobby":
            room.members.remove(member)
            member.room = None
            member.name, member.color = "", -1
        else:
            # En partida el asiento se conserva y el servidor juega por el.
            member.abandoned = True
            if member.connected:
                member.room = None  # quien se va a proposito queda libre
        if not room.alive_members():
            self._close_room(room)
            return
        if room.host_id == member.player_id:
            room.host_id = room.alive_members()[0].player_id
        self._broadcast_room(room)
        self._schedule_autoplay(room)

    def _close_room(self, room: Room) -> None:
        if room.autoplay_handle:
            room.autoplay_handle.cancel()
            room.autoplay_handle = None
        for m in room.members:
            if m.grace_handle:
                m.grace_handle.cancel()
            if m.room is room:
                m.room = None
            if not m.connected:
                self.sessions.pop(m.token, None)
        self.rooms.pop(room.code, None)
        log.info("Sala %s cerrada", room.code)

    def _reset_to_lobby(self, room: Room) -> None:
        # Quita a los que abandonaron o siguen desconectados, y vuelve al lobby.
        for m in list(room.members):
            if m.abandoned or not m.connected:
                room.members.remove(m)
                if m.room is room:
                    m.room = None
                if not m.connected:
                    self.sessions.pop(m.token, None)
        room.rules, room.seats, room.status = None, [], "lobby"
        if not room.members:
            self._close_room(room)
            return
        if room.host_id not in {m.player_id for m in room.members}:
            room.host_id = room.members[0].player_id
        self._broadcast_room(room)

    # ============================================================ difusion
    def _room_message(self, room: Room, member: Member) -> dict:
        seat_of = {id(m): i for i, m in enumerate(room.seats)} if room.rules else {}
        return {
            "type": "room_state",
            "room": {
                "code": room.code,
                "status": room.status,
                "host_id": room.host_id,
                "max_players": room.max_players,
                "members": [
                    {
                        "player_id": m.player_id,
                        "name": m.name,
                        "color": m.color,
                        "connected": m.connected,
                        "abandoned": m.abandoned,
                        "seat": seat_of.get(id(m)),
                    }
                    for m in room.members
                ],
            },
            "you": {"player_id": member.player_id, "seat": seat_of.get(id(member))},
        }

    def _broadcast_room(self, room: Room) -> None:
        for m in room.members:
            m.send(self._room_message(room, m))

    def _game_message(self, room: Room, event: Optional[dict]) -> dict:
        return {"type": "game_state", "state": room.rules.snapshot(), "event": event}

    def _broadcast_game(self, room: Room, event: Optional[dict]) -> None:
        message = self._game_message(room, event)
        for m in room.members:
            m.send(message)

    # ============================================================ utilidades
    def _require_no_room(self, member: Member) -> None:
        if member.room is not None:
            raise GameError("already_in_room", "Ya estas en una sala.")

    def _require_room(self, member: Member, status: Optional[str] = None) -> Room:
        room = member.room
        if room is None:
            raise GameError("not_in_room", "No estas en una sala.")
        if status and room.status != status:
            raise GameError("wrong_phase", "Accion no valida en este estado de la sala.")
        return room

    def _require_turn(self, member: Member) -> tuple[Room, int]:
        room = self._require_room(member)
        if room.status != "playing":
            raise GameError("wrong_phase", "No hay partida en curso.")
        seat = room.seats.index(member)
        if room.rules.current_player != seat:
            raise GameError("not_your_turn", "No es tu turno.")
        return room, seat

    @staticmethod
    def _member(room: Room, player_id: str) -> Member:
        return next(m for m in room.members if m.player_id == player_id)

    @staticmethod
    def _clean_name(raw: Any) -> str:
        name = " ".join(str(raw or "").split())
        if not name or len(name) > MAX_NAME:
            raise GameError("bad_name", f"El nombre debe tener entre 1 y {MAX_NAME} caracteres.")
        return name

    @staticmethod
    def _clean_color(raw: Any) -> int:
        if not isinstance(raw, int) or isinstance(raw, bool) or not 0 <= raw <= 3:
            raise GameError("bad_color", "El color debe ser un entero de 0 a 3.")
        return raw

    def _new_code(self) -> str:
        while True:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            if code not in self.rooms:
                return code
