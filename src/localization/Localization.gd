extends Node
## English is the source language. Only an explicit preference changes the UI locale.
const DEFAULT_LANGUAGE := "en"
const LANGUAGES := ["en", "es"]
var settings_path := "user://language.cfg"

func _enter_tree() -> void:
	restore()

func restore() -> void:
	var config := ConfigFile.new()
	var language := DEFAULT_LANGUAGE
	if config.load(settings_path) == OK:
		language = str(config.get_value("localization", "language", DEFAULT_LANGUAGE))
	set_language(language, false)

func set_language(language: String, persist: bool = true) -> void:
	var selected := language if language in LANGUAGES else DEFAULT_LANGUAGE
	TranslationServer.set_locale(selected)
	if persist:
		var config := ConfigFile.new()
		config.set_value("localization", "language", selected)
		var error := config.save(settings_path)
		if error != OK:
			push_warning("Could not save language preference: %s" % error_string(error))
