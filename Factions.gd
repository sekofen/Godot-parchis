class_name Factions
extends RefCounted
## Lore/presentation facade: faction choice never changes a legal move or dice odds.

const Manager := preload("res://src/factions/FactionManager.gd")

static func profile(faction_id: int) -> Dictionary:
	return Manager.get_faction(faction_id).to_legacy_profile()

static func briefing(faction_id: int, player_name: String, opening_player_name: String = "", opens_match: bool = true) -> Array[Dictionary]:
	return Manager.get_briefing(faction_id, player_name, opening_player_name, opens_match)

## Each expedition has a reason to cross the same gate; rules stay symmetrical.
static func expedition(faction_id: int) -> String:
	return Manager.get_expedition(faction_id)

static func reaction(faction_id: int, event: String) -> String:
	return Manager.get_reaction(faction_id, event)
