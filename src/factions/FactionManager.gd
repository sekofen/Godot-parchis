class_name FactionManager
extends RefCounted
## Faction resources are required game assets; Godot loads the configured translations.
const FACTIONS: Array[FactionData] = [
	preload("res://src/data/factions/crimson_vanguard.tres"),
	preload("res://src/data/factions/viridian_accord.tres"),
	preload("res://src/data/factions/azure_continuum.tres"),
	preload("res://src/data/factions/solar_corsairs.tres")
]

static func get_all_factions() -> Array[FactionData]:
	return FACTIONS

static func get_faction(faction_id: int) -> FactionData:
	return FACTIONS[faction_id]

static func get_briefing(faction_id: int, player_name: String, opening_player: String = "", opens_match: bool = true) -> Array[Dictionary]:
	return get_faction(faction_id).get_briefing_pages(player_name, opening_player, opens_match)

static func get_expedition(faction_id: int) -> String:
	return get_faction(faction_id).get_expedition()

static func get_reaction(faction_id: int, event: String) -> String:
	return str(TranslationServer.translate("FACTION_%d_REACT_%s" % [faction_id, event.to_upper()]))
