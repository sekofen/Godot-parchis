extends Control
class_name OptionsMenu

signal back_pressed
signal quit_match_pressed

# Audio sliders and labels
@onready var master_slider: HSlider = %MasterSlider
@onready var master_label: Label = %MasterValueLabel
@onready var music_slider: HSlider = %MusicSlider
@onready var music_label: Label = %MusicValueLabel
@onready var sfx_slider: HSlider = %SFXSlider
@onready var sfx_label: Label = %SFXValueLabel

# Display and gameplay
@onready var language_option: OptionButton = %LanguageOption
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var fast_anim_check: CheckBox = %FastAnimCheck
@onready var btn_back: Button = %BtnBack
@onready var btn_quit_match: Button = %BtnQuitMatch

var is_in_game: bool = false

func _ready() -> void:
	_init_language_control()
	_init_audio_controls()
	_init_display_controls()
	_init_gameplay_controls()
	btn_back.pressed.connect(_on_back_pressed)
	btn_quit_match.pressed.connect(_on_quit_match_pressed)
	set_in_game_mode(is_in_game)

func set_in_game_mode(in_game: bool) -> void:
	is_in_game = in_game
	btn_quit_match.visible = in_game
	btn_back.text = tr("OPTIONS_RESUME") if in_game else tr("UI_MAIN_MENU")

func _init_audio_controls() -> void:
	# Default mock values
	master_slider.value = 0.85
	music_slider.value = 0.70
	sfx_slider.value = 0.90
	
	_update_slider_label(master_slider.value, master_label)
	_update_slider_label(music_slider.value, music_label)
	_update_slider_label(sfx_slider.value, sfx_label)
	
	master_slider.value_changed.connect(func(val: float) -> void:
		_update_slider_label(val, master_label)
		_apply_bus_volume("Master", val)
	)
	music_slider.value_changed.connect(func(val: float) -> void:
		_update_slider_label(val, music_label)
		_apply_bus_volume("Music", val)
	)
	sfx_slider.value_changed.connect(func(val: float) -> void:
		_update_slider_label(val, sfx_label)
		_apply_bus_volume("SFX", val)
	)

func _update_slider_label(value: float, label: Label) -> void:
	label.text = "%d%%" % int(round(value * 100.0))

func _apply_bus_volume(bus_name: String, linear_value: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear_value))
		AudioServer.set_bus_mute(bus_idx, linear_value <= 0.01)

func _init_display_controls() -> void:
	var mode := DisplayServer.window_get_mode()
	fullscreen_check.button_pressed = (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("[OptionsMenu] Fullscreen enabled.")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		print("[OptionsMenu] Windowed mode enabled.")

func _init_gameplay_controls() -> void:
	fast_anim_check.button_pressed = false
	fast_anim_check.toggled.connect(func(pressed: bool) -> void:
		print("[OptionsMenu] Quick dice animations: %s" % ("enabled" if pressed else "disabled"))
	)

func _on_back_pressed() -> void:
	print("[OptionsMenu] Returning...")
	back_pressed.emit()

func _on_quit_match_pressed() -> void:
	print("[OptionsMenu] Leaving match for main menu...")
	quit_match_pressed.emit()
	get_tree().change_scene_to_file("res://src/UI/menus/MenuManager.tscn")

func _init_language_control() -> void:
	# Autonyms make both choices recognizable in either language.
	language_option.add_item("English", 0)
	language_option.add_item("Español", 1)
	_refresh_language_control()
	language_option.item_selected.connect(func(index: int) -> void:
		Localization.set_language(Localization.LANGUAGES[index])
	)

func _refresh_language_control() -> void:
	language_option.select(Localization.LANGUAGES.find(TranslationServer.get_locale()))
	set_in_game_mode(is_in_game)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_language_control()
