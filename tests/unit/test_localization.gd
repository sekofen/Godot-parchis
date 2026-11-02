extends "res://tests/support/test_case.gd"
## Exercise catalogs, startup policy, persistence, and language changes in real screens.
const LocaleSettings := preload("res://src/localization/Localization.gd")
const Rules := preload("res://ParquesRules.gd")
var catalog: Dictionary = {}

func _run() -> void:
	_load_catalog()
	_check_catalog()
	_check_source_keys("res://")
	_test_preferences()
	await _test_menus()
	await _test_match()
	TranslationServer.set_locale("en")
	await finish("complete catalogs, English defaults, preference persistence, menus and live match localization")

func _load_catalog() -> void:
	var file := FileAccess.open("res://src/localization/translations.csv", FileAccess.READ)
	check(file.get_csv_line() == PackedStringArray(["keys", "en", "es"]), "Catalog defines English and Spanish")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		check(row.size() == 3, "Each catalog row has both translations")
		check(not catalog.has(row[0]), "Translation keys are unique: " + row[0])
		catalog[row[0]] = [row[1], row[2]]

func _check_catalog() -> void:
	var placeholders := RegEx.new()
	placeholders.compile("\\{[^}]+\\}|%[sdif]")
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		var column := 0 if locale == "en" else 1
		for key in catalog:
			var expected: String = catalog[key][column]
			check(not expected.strip_edges().is_empty(), "Translation is nonempty: %s/%s" % [key, locale])
			check(TranslationServer.translate(key) == expected, "Imported catalog matches source: %s/%s" % [key, locale])
			var source_tokens: Array[String] = []
			var target_tokens: Array[String] = []
			for found in placeholders.search_all(catalog[key][0]):
				source_tokens.append(found.get_string())
			for found in placeholders.search_all(expected):
				target_tokens.append(found.get_string())
			check(source_tokens == target_tokens, "Placeholder names and order agree: %s/%s" % [key, locale])

func _check_source_keys(path: String) -> void:
	var directory := DirAccess.open(path)
	for name in directory.get_files():
		if not (name.ends_with(".gd") or name.ends_with(".tscn")):
			continue
		var source := FileAccess.get_file_as_string(path.path_join(name))
		var pattern := RegEx.new()
		pattern.compile('tr\\("([A-Z][A-Z_0-9]+)"\\)')
		for found in pattern.search_all(source):
			check(catalog.has(found.get_string(1)), "Code translation key exists: " + found.get_string(1))
		if name.ends_with(".tscn"):
			pattern.compile('(?m)^(?:text|tooltip_text|placeholder_text) = "([^"]+)"')
			for found in pattern.search_all(source):
				var value := found.get_string(1)
				var fixed := value in ["PARQUÉS", "T H E  L O O M", "PARQUE-4821", "85%", "70%", "90%"] or value.is_valid_int()
				check(fixed or catalog.has(value), "Scene text uses the catalog: %s/%s" % [name, value])
	for child in directory.get_directories():
		if not child.begins_with(".") and child not in ["tests", "tools", "artifacts", "build", "assets", "node_modules"]:
			_check_source_keys(path.path_join(child))

func _test_preferences() -> void:
	var settings := LocaleSettings.new()
	settings.settings_path = "user://test-language-%d.cfg" % Time.get_ticks_usec()
	TranslationServer.set_locale("es")
	settings.restore()
	check(TranslationServer.get_locale() == "en", "Fresh preferences use English regardless of system locale")
	settings.set_language("es")
	var restored := LocaleSettings.new()
	restored.settings_path = settings.settings_path
	restored.restore()
	check(TranslationServer.get_locale() == "es", "Explicit Spanish preference survives reload")
	settings.set_language("unsupported")
	check(TranslationServer.get_locale() == "en", "Unsupported language falls back to English")
	restored.restore()
	check(TranslationServer.get_locale() == "en", "Fallback persists as a supported language")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.settings_path))
	settings.free()
	restored.free()

func _test_menus() -> void:
	TranslationServer.set_locale("en")
	var menus: Control = load("res://src/UI/menus/MenuManager.tscn").instantiate()
	root.add_child(menus)
	await process_frame
	var slot: PlayerSlot = menus.local_setup.slot_instances[0]
	var other: PlayerSlot = menus.local_setup.slot_instances[1]
	slot.name_input.text = "Lucía {Pilot}"
	other.faction_option.select(3)
	menus.multiplayer_menu._reset_host_lobby()
	menus.multiplayer_menu._on_simulate_remote_player_connected()
	var remote: PlayerSlot = menus.multiplayer_menu.host_slot_instances[1]
	var remote_name := remote.name_input.text
	for locale in ["es", "en"]:
		TranslationServer.set_locale(locale)
		await process_frame
		check(menus.main_menu.btn_local.tr(menus.main_menu.btn_local.text) == ("Local match" if locale == "en" else "Partida local"), "Main menu follows selected language")
		check(slot.name_input.text == "Lucía {Pilot}", "Player-entered names survive language changes")
		check(other.name_input.text == ("Player 2" if locale == "en" else "Jugador 2"), "Generated defaults follow language")
		check(other.faction_option.get_selected_id() == 3, "Faction selection survives language changes")
		check(other.faction_option.get_item_text(3) == ("Solar Corsairs (Yellow)" if locale == "en" else "Corsarios Solares (Amarillo)"), "Faction names and colors are localized together")
		check(menus.options_menu.btn_back.text == ("Return to main menu" if locale == "en" else "Volver al menú principal"), "Options navigation follows language")
		check(menus.options_menu.language_option.selected == (0 if locale == "en" else 1), "Language selector tracks active language")
		check(remote.name_input.text == remote_name and not remote.name_input.editable, "Remote identity and permissions survive language changes")
		check(remote.role_badge.text == ("CONNECTED" if locale == "en" else "CONECTADO"), "Connection badges follow language")
		check(menus.multiplayer_menu.host_slot_instances[0].name_input.text == ("Host (You)" if locale == "en" else "Anfitrión (Tú)"), "Generated host identity follows language")
		menus.local_setup.slot_instances[1].name_input.text = ""
		menus.local_setup._on_start_pressed()
		check(menus.local_setup.status_label.text == ("Player 2 must have a name." if locale == "en" else "El jugador 2 debe tener un nombre."), "Setup validation uses selected language")
		menus.local_setup.slot_instances[1].name_input.text = other._generated_name
	# Exercise the actual selector with isolated storage instead of changing user preferences.
	var localization := root.get_node("Localization")
	var original_path: String = localization.settings_path
	localization.settings_path = "user://test-selector-%d.cfg" % Time.get_ticks_usec()
	menus.options_menu.language_option.item_selected.emit(1)
	check(TranslationServer.get_locale() == "es", "Options selector changes the application language")
	var saved := ConfigFile.new()
	check(saved.load(localization.settings_path) == OK and saved.get_value("localization", "language") == "es", "Options selector saves the preference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(localization.settings_path))
	localization.settings_path = original_path
	menus.queue_free()
	await process_frame

func _test_match() -> void:
	TranslationServer.set_locale("en")
	var scene := load_game()
	await process_frame
	check(TranslationServer.get_locale() == "en", "Board controls never override the locale")
	scene.name_inputs[0].text = "Lucía {Pilot}"
	scene._start_match()
	scene.game.roll(6, 5)
	scene.game.roll(1, 2)
	scene.faction_briefing.finish()
	scene.game.roll(2, 2)
	scene._select_pawn(0)
	scene._add_log("LOG_ROLL", ["Lucía {Pilot}", 2, 2])
	var state: Array = scene.game.pawns.duplicate(true)
	for locale in ["es", "en"]:
		TranslationServer.set_locale(locale)
		await process_frame
		await process_frame
		check(scene.command_dock.size.x <= scene.SIDEBAR_WIDTH + 1, "Translated sidebar stays within its reserved width")
		check(scene.command_dock.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Translated sidebar stays on screen")
		check(scene.game.pawns == state and scene.game.phase == "move", "Language changes preserve match state")
		check(scene._selected == 0, "Selected pawn survives language changes")
		check(scene.choices.get_child(0).text.begins_with("Release to" if locale == "en" else "Salir a"), "Legal move descriptions follow language")
		check(scene.move_overlay.get_node("move_0").text == ("LAUNCH" if locale == "en" else "SALIR"), "Board launch target follows language")
		check(scene.history_label.text == ("Lucía {Pilot} rolled 2 + 2" if locale == "en" else "Lucía {Pilot} lanzó 2 + 2"), "Existing history is retranslated without editing player names")
		check(scene.game.notice.begins_with("Select a glowing pawn" if locale == "en" else "Elige una ficha iluminada"), "Existing rules notice follows language")
		check(scene.dice_labels[0].tooltip_text == ("2 · available" if locale == "en" else "2 · disponible"), "Dice tooltips follow language")
		check(scene.options_overlay.btn_back.text == ("Continue match" if locale == "en" else "Continuar partida"), "Match options navigation follows language")
	# Re-translate an open briefing rather than restarting it or changing whose turn it is.
	scene.faction_briefing.present(0, "Lucía {Pilot}", "Rival", false)
	TranslationServer.set_locale("es")
	await process_frame
	check("Lucía {Pilot}" in scene.faction_briefing.dialogue.text and "Rival" in scene.faction_briefing.dialogue.text, "Briefing preserves supplied names")
	check(scene.faction_briefing.page_title.text == "EL TELAR ESTÁ DESPERTANDO", "Open briefing follows language")
	check("\\n" not in scene.faction_briefing.dialogue.text and "\n\n" in scene.faction_briefing.dialogue.text, "Dialogue contains real paragraph breaks")
	scene.faction_briefing.finish()
	# A language change during an animation must not resynchronize or move the pawn.
	scene._busy = true
	var pawn: Node3D = scene.board.pawn_nodes[0][0]
	var position := pawn.position + Vector3(0, 2, 0)
	pawn.position = position
	TranslationServer.set_locale("en")
	await process_frame
	check(pawn.position.is_equal_approx(position), "Changing language does not interrupt an in-flight pawn")
	scene._busy = false
	scene.game.pawns[0] = [Rules.GOAL, Rules.GOAL, Rules.GOAL, Rules.GOAL]
	scene.game._check_win()
	scene._refresh()
	TranslationServer.set_locale("es")
	await process_frame
	check(scene.victory_overlay.find_child("WinnerLabel", true, false).text == "¡Lucía {Pilot} gana!", "Visible winner announcement follows language")
	scene.queue_free()
	await process_frame
