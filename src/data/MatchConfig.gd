extends Node

## Transfers match setup from LocalSetup / MultiplayerMenu
## to the 3D game scene (MainGame.tscn / GameController.gd).
## Registered as the MatchConfig autoload in project.godot.

var pending_players: Array[Dictionary] = []
var pending_fast_dice: bool = false

## Registers player configuration for a local match:
## players must contain dictionaries with 'name' and 'faction_id' or 'color'.
func set_local_match(players: Array[Dictionary], fast_dice: bool = false) -> void:
	pending_players.clear()
	for p in players:
		var color_val: int = int(p.get("faction_id", p.get("color", 0)))
		var name_val: String = str(p.get("name", tr("SLOT_DEFAULT_NAME") % (pending_players.size() + 1))).strip_edges()
		pending_players.append({
			"name": name_val,
			"color": color_val
		})
	pending_fast_dice = fast_dice
	print("[MatchConfig] Match configuration stored for %d players: %s" % [pending_players.size(), str(pending_players)])

func has_pending_match() -> bool:
	return pending_players.size() >= 2

func consume_match_players() -> Array[Dictionary]:
	var result := pending_players.duplicate(true)
	pending_players.clear()
	return result

func clear() -> void:
	pending_players.clear()
	pending_fast_dice = false
