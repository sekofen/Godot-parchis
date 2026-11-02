extends "res://tests/support/test_case.gd"

const FactionMgr := preload("res://src/factions/FactionManager.gd")
const Lore := preload("res://Factions.gd")

func _run() -> void:
	var factions := FactionMgr.get_all_factions()
	check(factions.size() == 4, "Loaded four faction data resources")
	for index in range(factions.size()):
		check(factions[index].id == index, "Faction resources are ordered by color ID")
		check(factions[index].resource_path.begins_with("res://src/data/factions/"), "Faction data comes from a packaged resource")

	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		_verify_placeholders_in_briefings(locale)
		_verify_placeholders_in_welcome_and_prologue(locale)

	# Verify UI tree in a real match
	TranslationServer.set_locale("en")
	var scene := load_game()
	await process_frame
	_check_node_texts_recursively(scene, "Game Scene (English)")

	# Verify Faction Briefing dialog presentations
	for fid in range(4):
		scene.faction_briefing.present(fid, "Commander Shepard", "Pilot Joker", true)
		_check_node_texts_recursively(scene.faction_briefing, "FactionBriefing Present (Winner, Faction %d)" % fid)

		scene.faction_briefing.present(fid, "Commander Shepard", "Pilot Joker", false)
		_check_node_texts_recursively(scene.faction_briefing, "FactionBriefing Present (Observer, Faction %d)" % fid)

	# Test Spanish UI
	TranslationServer.set_locale("es")
	for fid in range(4):
		scene.faction_briefing.present(fid, "Comandante Shepard", "Piloto Joker", true)
		_check_node_texts_recursively(scene.faction_briefing, "FactionBriefing Spanish (Winner, Faction %d)" % fid)

		scene.faction_briefing.present(fid, "Comandante Shepard", "Piloto Joker", false)
		_check_node_texts_recursively(scene.faction_briefing, "FactionBriefing Spanish (Observer, Faction %d)" % fid)

	TranslationServer.set_locale("en")
	finish("Placeholder substitution verified: zero unreplaced brackets found in UI or dialogues.")

func _verify_placeholders_in_briefings(locale: String) -> void:
	for fid in range(4):
		var pages_self := Lore.briefing(fid, "Tester", "Rival", true)
		for p in pages_self:
			_assert_no_brackets(p.get("title", ""), "Briefing title (fid %d, %s)" % [fid, locale])
			_assert_no_brackets(p.get("text", ""), "Briefing text (fid %d, %s)" % [fid, locale])

		var pages_obs := Lore.briefing(fid, "Tester", "Rival", false)
		for p in pages_obs:
			_assert_no_brackets(p.get("title", ""), "Briefing title obs (fid %d, %s)" % [fid, locale])
			_assert_no_brackets(p.get("text", ""), "Briefing text obs (fid %d, %s)" % [fid, locale])

func _verify_placeholders_in_welcome_and_prologue(locale: String) -> void:
	for fid in range(4):
		var f := FactionMgr.get_faction(fid)
		var welcome_win := f.get_welcome("Hero", "Rival", true)
		_assert_no_brackets(welcome_win, "Faction %d get_welcome winner (%s)" % [fid, locale])
		check("Hero" in welcome_win, "Hero name injected in welcome winner (%s)" % locale)

		var welcome_obs := f.get_welcome("Hero", "Rival", false)
		_assert_no_brackets(welcome_obs, "Faction %d get_welcome observer (%s)" % [fid, locale])
		check("Hero" in welcome_obs and "Rival" in welcome_obs, "Hero and Rival names injected in welcome observer (%s)" % locale)

func _assert_no_brackets(text: String, context: String) -> void:
	var has_unreplaced := text.contains("{") or text.contains("}")
	check(not has_unreplaced, "No unreplaced brackets in: %s -> Output was: '%s'" % [context, text.left(60)])

func _check_node_texts_recursively(node: Node, context: String) -> void:
	if not is_instance_valid(node):
		return

	if node is Label:
		_assert_no_brackets(node.text, "%s -> Label '%s'" % [context, node.name])
	elif node is Button:
		_assert_no_brackets(node.text, "%s -> Button '%s'" % [context, node.name])
	elif node is RichTextLabel:
		_assert_no_brackets(node.text, "%s -> RichTextLabel '%s'" % [context, node.name])
	elif node is LineEdit:
		_assert_no_brackets(node.text, "%s -> LineEdit '%s'" % [context, node.name])
		_assert_no_brackets(node.placeholder_text, "%s -> LineEdit placeholder '%s'" % [context, node.name])
	elif node is OptionButton:
		for i in range(node.item_count):
			_assert_no_brackets(node.get_item_text(i), "%s -> OptionButton item %d '%s'" % [context, i, node.name])

	for child in node.get_children():
		_check_node_texts_recursively(child, context)
