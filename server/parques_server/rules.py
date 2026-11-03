"""Puerto fiel a Python de ParquesRules.gd (estado puro del juego).

Los dados los suministra quien llama (el servidor), asi las reglas son
deterministas y testeables. El progreso de una ficha es -1 en la carcel y
0 en la salida.
"""
from __future__ import annotations

CIRCUIT = 96
SECTOR = 24
LAUNCH_OFFSET = 3
GATE_OFFSET = 11
HOME_LENGTH = 10
TRACK_STEPS = 88
GOAL = TRACK_STEPS + HOME_LENGTH + 1
FINISHED = GOAL
SAFE_OFFSETS = (LAUNCH_OFFSET, 8, 14, 20)


class ParquesRules:
    def __init__(self) -> None:
        self.players: list[dict] = []
        self.pawns: list[list[int]] = []
        self.current_player = 0
        self.phase = "lobby"  # lobby, opening, await_roll, move, bonus, game_over
        self.winner = -1
        self.last_roll: list[int] = []
        self.dice_remaining = [False, False]
        self.consecutive_doubles = 0
        self.jail_attempts = 3
        self.notice = ""
        self.captured: list[dict] = []
        self._opening_candidates: list[int] = []
        self._opening_scores: dict[int, int] = {}
        self._opening_cursor = 0

    # ------------------------------------------------------------ setup
    def configure(self, entries: list[dict]) -> bool:
        if self.phase != "lobby":
            return False
        if not 2 <= len(entries) <= 4:
            return False
        colors: set[int] = set()
        for entry in entries:
            if "name" not in entry or "color" not in entry:
                return False
            try:
                color = int(entry["color"])
            except (TypeError, ValueError):
                return False
            if not str(entry["name"]).strip() or not 0 <= color <= 3 or color in colors:
                return False
            colors.add(color)
        self.players = [
            {"name": str(e["name"]).strip(), "color": int(e["color"])} for e in entries
        ]
        self.pawns = [[-1, -1, -1, -1] for _ in entries]
        self.winner = -1
        self.last_roll = []
        self.dice_remaining = [False, False]
        self.consecutive_doubles = 0
        self.jail_attempts = 3
        self.captured = []
        self._opening_candidates = list(range(len(entries)))
        self._opening_scores = {}
        self._opening_cursor = 0
        self.current_player = 0
        self.phase = "opening"
        self.notice = "Roll to determine the first player. Highest total starts."
        return True

    # ------------------------------------------------------------ roll
    def roll(self, a: int, b: int) -> bool:
        if self.phase not in ("opening", "await_roll") or not (1 <= a <= 6 and 1 <= b <= 6):
            return False
        self.last_roll = [a, b]
        self.captured = []
        if self.phase == "opening":
            self._resolve_opening(a + b)
            return True
        self.dice_remaining = [True, True]
        if a == b:
            self.consecutive_doubles += 1
        else:
            self.consecutive_doubles = 0
        if self.consecutive_doubles == 3:
            self.phase = "bonus"
            self.dice_remaining = [False, False]
            self.notice = "Three consecutive doubles! Select any unfinished pawn to send to the goal."
        elif not self.legal_moves():
            self.dice_remaining = [False, False]
            if a == b:
                self.phase = "await_roll"
                self.notice = f"Doubles, but no legal landing. Roll again ({self.consecutive_doubles}/3)."
            elif self._all_unfinished_in_jail() and self.jail_attempts > 1:
                self.jail_attempts -= 1
                self.phase = "await_roll"
                self.notice = f"No doubles. {self.jail_attempts} jail-release attempt(s) left."
            else:
                self._advance_turn("No legal moves.")
        else:
            self.phase = "move"
            self.notice = "Select a glowing pawn, then a landing space. Use each die whole, or combine both."
        return True

    def _resolve_opening(self, total: int) -> None:
        self._opening_scores[self.current_player] = total
        self._opening_cursor += 1
        if self._opening_cursor < len(self._opening_candidates):
            self.current_player = self._opening_candidates[self._opening_cursor]
            self.notice = f"{self.players[self.current_player]['name']}: roll for starting order."
            return
        highest = -1
        tied: list[int] = []
        for index in self._opening_candidates:
            score = self._opening_scores[index]
            if score > highest:
                highest = score
                tied = [index]
            elif score == highest:
                tied.append(index)
        if len(tied) > 1:
            self._opening_candidates = tied
            self._opening_scores = {}
            self._opening_cursor = 0
            self.current_player = tied[0]
            self.notice = f"Tie at {highest}. Tied players roll again."
        else:
            self._begin_turn(tied[0])
            self.notice = (
                f"{self.players[self.current_player]['name']} starts with {highest}. "
                "Roll doubles to leave jail."
            )

    # ------------------------------------------------------------ moves
    def legal_moves(self) -> list[dict]:
        result: list[dict] = []
        if self.phase not in ("await_roll", "move") or len(self.last_roll) != 2:
            return result
        for pawn in range(4):
            progress = self.pawns[self.current_player][pawn]
            if progress == FINISHED:
                continue
            if progress == -1:
                if (
                    self.dice_remaining[0]
                    and self.dice_remaining[1]
                    and self.last_roll[0] == self.last_roll[1]
                ):
                    result.append({"pawn": pawn, "mask": 3, "steps": 0, "target": 0, "kind": "release"})
                continue
            for mask in (1, 2, 3):
                if (mask & 1 and not self.dice_remaining[0]) or (mask & 2 and not self.dice_remaining[1]):
                    continue
                # Dados iguales: los movimientos de un solo dado son equivalentes.
                if mask == 2 and self.dice_remaining[0] and self.last_roll[0] == self.last_roll[1]:
                    continue
                steps = 0
                if mask & 1:
                    steps += self.last_roll[0]
                if mask & 2:
                    steps += self.last_roll[1]
                if progress + steps <= GOAL:
                    result.append(
                        {"pawn": pawn, "mask": mask, "steps": steps, "target": progress + steps, "kind": "move"}
                    )
        return result

    def play(self, pawn: int, mask: int) -> bool:
        if self.phase != "move":
            return False
        choice = next(
            (m for m in self.legal_moves() if m["pawn"] == pawn and m["mask"] == mask), None
        )
        if choice is None:
            return False
        self.captured = []
        self.pawns[self.current_player][pawn] = choice["target"]
        if mask & 1:
            self.dice_remaining[0] = False
        if mask & 2:
            self.dice_remaining[1] = False
        cell = self.circuit_index(self.current_player, choice["target"])
        if cell >= 0 and not self.is_protected(cell):
            for opponent in range(len(self.players)):
                if opponent == self.current_player:
                    continue
                for rival in range(4):
                    if self.circuit_index(opponent, self.pawns[opponent][rival]) == cell:
                        self.pawns[opponent][rival] = -1
                        self.captured.append({"player": opponent, "pawn": rival})
        action = ""
        if choice["kind"] == "release":
            action = "Pawn released. Roll again to move."
        elif choice["target"] == FINISHED:
            action = "Pawn reached the goal!"
        elif self.captured:
            action = f"Captured {len(self.captured)} rival pawn(s)!"
        if self._check_win():
            return True
        if self.legal_moves():
            self.notice = action + " Use the remaining die."
        else:
            self.dice_remaining = [False, False]
            if self.last_roll[0] == self.last_roll[1]:
                self.phase = "await_roll"
                self.notice = f"{action} Doubles: roll again ({self.consecutive_doubles}/3)."
            else:
                self._advance_turn(action)
        return True

    def claim_bonus(self, pawn: int) -> bool:
        if (
            self.phase != "bonus"
            or not 0 <= pawn < 4
            or self.pawns[self.current_player][pawn] == FINISHED
        ):
            return False
        self.pawns[self.current_player][pawn] = FINISHED
        self.consecutive_doubles = 0
        if not self._check_win():
            self.phase = "await_roll"
            self.notice = "Bonus pawn reached the goal. Roll again."
        return True

    # ------------------------------------------------------------ helpers
    def circuit_index(self, player: int, progress: int) -> int:
        if progress < 0 or progress > TRACK_STEPS:
            return -1
        return (self.players[player]["color"] * SECTOR + LAUNCH_OFFSET - progress) % CIRCUIT

    @staticmethod
    def is_protected(cell: int) -> bool:
        return cell % SECTOR in SAFE_OFFSETS

    def finished_count(self, player: int) -> int:
        return self.pawns[player].count(FINISHED)

    def _all_unfinished_in_jail(self) -> bool:
        return all(p == -1 or p == FINISHED for p in self.pawns[self.current_player])

    def _check_win(self) -> bool:
        if self.finished_count(self.current_player) != 4:
            return False
        self.winner = self.current_player
        self.phase = "game_over"
        self.dice_remaining = [False, False]
        self.notice = f"{self.players[self.winner]['name']} wins! All four pawns reached the goal."
        return True

    def _advance_turn(self, prefix: str = "") -> None:
        # Los asientos giran a la derecha; se saltan los colores vacios.
        nxt = self.current_player
        color_id = self.players[self.current_player]["color"]
        for distance in range(1, 5):
            next_color = (color_id - distance) % 4
            for index, player in enumerate(self.players):
                if player["color"] == next_color:
                    nxt = index
                    break
            if nxt != self.current_player:
                break
        self._begin_turn(nxt)
        self.notice = (prefix + " " if prefix else "") + f"{self.players[self.current_player]['name']}'s turn. Roll the dice."

    def _begin_turn(self, player: int) -> None:
        self.current_player = player
        self.phase = "await_roll"
        self.dice_remaining = [False, False]
        self.consecutive_doubles = 0
        self.jail_attempts = 3

    # ------------------------------------------------------------ snapshot
    def snapshot(self) -> dict:
        """Estado completo serializable para enviar a los clientes."""
        return {
            "players": [dict(p) for p in self.players],
            "pawns": [list(row) for row in self.pawns],
            "current_player": self.current_player,
            "phase": self.phase,
            "winner": self.winner,
            "last_roll": list(self.last_roll),
            "dice_remaining": list(self.dice_remaining),
            "consecutive_doubles": self.consecutive_doubles,
            "jail_attempts": self.jail_attempts,
            "notice": self.notice,
            "captured": [dict(c) for c in self.captured],
            "legal_moves": self.legal_moves(),
        }
