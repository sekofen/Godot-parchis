class_name ParquesRules
extends RefCounted
## Pure game state. Dice are supplied by the controller, making rules deterministic
## and independently testable. A pawn's progress is -1 in jail, 0 at salida.
signal changed

const CIRCUIT := 96
const SECTOR := 24
const LAUNCH_OFFSET := 3
const GATE_OFFSET := 11
const HOME_LENGTH := 10
const TRACK_STEPS := 88 # Counterclockwise from salida to own entrance.
const GOAL := TRACK_STEPS + HOME_LENGTH + 1
const FINISHED := GOAL

var players: Array[Dictionary] = []
var pawns: Array = []
var current_player := 0
var phase := "lobby" # lobby, opening, await_roll, move, bonus, game_over
var winner := -1
var last_roll: Array[int] = []
var dice_remaining: Array[bool] = [false, false]
var consecutive_doubles := 0
var jail_attempts := 3
var _notice_parts: Array[Dictionary] = []
var notice: String:
	get:
		var parts: PackedStringArray = []
		for part in _notice_parts:
			parts.append(tr(part.key) % part.values)
		return " ".join(parts)
var captured: Array[Dictionary] = []
var _opening_candidates: Array[int] = []
var _opening_scores: Dictionary = {}
var _opening_cursor := 0

func configure(entries: Array[Dictionary]) -> bool:
	if phase != "lobby":
		return false
	if entries.size() < 2 or entries.size() > 4:
		return false
	var colors := {}
	for entry in entries:
		if not entry.has("name") or not entry.has("color"):
			return false
		var color_id := int(entry.color)
		if str(entry.name).strip_edges().is_empty() or color_id < 0 or color_id > 3 or colors.has(color_id):
			return false
		colors[color_id] = true
	players.clear()
	pawns.clear()
	for entry in entries:
		players.append({"name": str(entry.name).strip_edges(), "color": int(entry.color)})
		pawns.append([-1, -1, -1, -1])
	winner = -1
	last_roll.clear()
	dice_remaining = [false, false]
	consecutive_doubles = 0
	jail_attempts = 3
	captured.clear()
	_opening_candidates.clear()
	_opening_scores.clear()
	for index in range(players.size()):
		_opening_candidates.append(index)
	_opening_cursor = 0
	current_player = 0
	phase = "opening"
	_set_notice(_message("RULES_OPENING"))
	changed.emit()
	return true

func roll(a: int, b: int) -> bool:
	if phase not in ["opening", "await_roll"] or a < 1 or a > 6 or b < 1 or b > 6:
		return false
	last_roll.assign([a, b])
	captured.clear()
	if phase == "opening":
		_resolve_opening(a + b)
		changed.emit()
		return true
	dice_remaining = [true, true]
	if a == b:
		consecutive_doubles += 1
	else:
		consecutive_doubles = 0
	if consecutive_doubles == 3:
		phase = "bonus"
		dice_remaining = [false, false]
		_set_notice(_message("RULES_THIRD_DOUBLE"))
	elif legal_moves().is_empty():
		dice_remaining = [false, false]
		if a == b:
			phase = "await_roll"
			_set_notice(_message("RULES_NO_LANDING_DOUBLES", [consecutive_doubles]))
		elif _all_unfinished_in_jail() and jail_attempts > 1:
			jail_attempts -= 1
			phase = "await_roll"
			_set_notice(_message("RULES_JAIL_ATTEMPTS", [jail_attempts]))
		else:
			_advance_turn(_message("RULES_NO_MOVES"))
	else:
		phase = "move"
		_set_notice(_message("RULES_SELECT"))
	changed.emit()
	return true

func _resolve_opening(total: int) -> void:
	_opening_scores[current_player] = total
	_opening_cursor += 1
	if _opening_cursor < _opening_candidates.size():
		current_player = _opening_candidates[_opening_cursor]
		_set_notice(_message("RULES_OPENING_PLAYER", [players[current_player].name]))
		return
	var highest := -1
	var tied: Array[int] = []
	for index in _opening_candidates:
		var score := int(_opening_scores[index])
		if score > highest:
			highest = score
			tied.assign([index])
		elif score == highest:
			tied.append(index)
	if tied.size() > 1:
		_opening_candidates.assign(tied)
		_opening_scores.clear()
		_opening_cursor = 0
		current_player = tied[0]
		_set_notice(_message("RULES_TIE", [highest]))
	else:
		_begin_turn(tied[0])
		_set_notice(_message("RULES_STARTER", [players[current_player].name, highest]))

func legal_moves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if phase not in ["await_roll", "move"] or last_roll.size() != 2:
		return result
	for pawn in range(4):
		var progress := int(pawns[current_player][pawn])
		if progress == FINISHED:
			continue
		if progress == -1:
			if dice_remaining[0] and dice_remaining[1] and last_roll[0] == last_roll[1]:
				result.append({"pawn": pawn, "mask": 3, "steps": 0, "target": 0, "kind": "release"})
			continue
		for mask in [1, 2, 3]:
			if (mask & 1 and not dice_remaining[0]) or (mask & 2 and not dice_remaining[1]):
				continue
			# Equal dice have equivalent single-die moves; offer the first available.
			if mask == 2 and dice_remaining[0] and last_roll[0] == last_roll[1]:
				continue
			var steps := 0
			if mask & 1:
				steps += last_roll[0]
			if mask & 2:
				steps += last_roll[1]
			if progress + steps <= GOAL:
				result.append({"pawn": pawn, "mask": mask, "steps": steps, "target": progress + steps, "kind": "move"})
	return result

func play(pawn: int, mask: int) -> bool:
	if phase != "move":
		return false
	var choice: Dictionary = {}
	for move in legal_moves():
		if move.pawn == pawn and move.mask == mask:
			choice = move
			break
	if choice.is_empty():
		return false
	captured.clear()
	pawns[current_player][pawn] = choice.target
	if mask & 1:
		dice_remaining[0] = false
	if mask & 2:
		dice_remaining[1] = false
	var cell := circuit_index(current_player, choice.target)
	if cell >= 0 and not is_protected(cell):
		for opponent in range(players.size()):
			if opponent == current_player:
				continue
			for rival in range(4):
				if circuit_index(opponent, int(pawns[opponent][rival])) == cell:
					pawns[opponent][rival] = -1
					captured.append({"player": opponent, "pawn": rival})
	var action: Dictionary = {}
	if choice.kind == "release":
		action = _message("RULES_RELEASE")
	elif choice.target == FINISHED:
		action = _message("RULES_GOAL")
	elif not captured.is_empty():
		action = _message("RULES_CAPTURE", [captured.size()])
	if _check_win():
		changed.emit()
		return true
	if not legal_moves().is_empty():
		_set_notice(action, _message("RULES_REMAINING"))
	else:
		dice_remaining = [false, false]
		if last_roll[0] == last_roll[1]:
			phase = "await_roll"
			_set_notice(action, _message("RULES_DOUBLE_AGAIN", [consecutive_doubles]))
		else:
			_advance_turn(action)
	changed.emit()
	return true

func claim_bonus(pawn: int) -> bool:
	if phase != "bonus" or pawn < 0 or pawn >= 4 or pawns[current_player][pawn] == FINISHED:
		return false
	pawns[current_player][pawn] = FINISHED
	consecutive_doubles = 0
	if not _check_win():
		phase = "await_roll"
		_set_notice(_message("RULES_BONUS"))
	changed.emit()
	return true

func circuit_index(player: int, progress: int) -> int:
	if progress < 0 or progress > TRACK_STEPS:
		return -1
	return posmod(int(players[player].color) * SECTOR + LAUNCH_OFFSET - progress, CIRCUIT)

func is_protected(cell: int) -> bool:
	return posmod(cell, SECTOR) in [LAUNCH_OFFSET, 8, 14, 20]

func finished_count(player: int) -> int:
	return pawns[player].count(FINISHED)

func _all_unfinished_in_jail() -> bool:
	for progress in pawns[current_player]:
		if progress >= 0 and progress != FINISHED:
			return false
	return true

func _check_win() -> bool:
	if finished_count(current_player) != 4:
		return false
	winner = current_player
	phase = "game_over"
	dice_remaining = [false, false]
	_set_notice(_message("RULES_WINNER", [players[winner].name]))
	return true

func _advance_turn(prefix: Dictionary = {}) -> void:
	# Lobby seats run around the board to the right; skip unoccupied colors.
	var next := current_player
	var color_id := int(players[current_player].color)
	for distance in range(1, 5):
		var next_color := posmod(color_id - distance, 4)
		for index in range(players.size()):
			if players[index].color == next_color:
				next = index
				break
		if next != current_player:
			break
	_begin_turn(next)
	_set_notice(prefix, _message("RULES_NEXT_TURN", [players[current_player].name]))

func _begin_turn(player: int) -> void:
	current_player = player
	phase = "await_roll"
	dice_remaining = [false, false]
	consecutive_doubles = 0
	jail_attempts = 3

# Store message identities so notices follow language changes without touching game state.
func _message(key: String, values: Array = []) -> Dictionary:
	return {"key": key, "values": values}

func _set_notice(first: Dictionary, second: Dictionary = {}) -> void:
	_notice_parts.clear()
	for part in [first, second]:
		if not part.is_empty():
			_notice_parts.append(part)
