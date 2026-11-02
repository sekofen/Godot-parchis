extends Control
class_name MainMenu

signal local_selected
signal multiplayer_selected
signal tutorial_selected
signal options_selected
signal quit_selected

@onready var btn_local: Button = %BtnLocal
@onready var btn_multiplayer: Button = %BtnMultiplayer
@onready var btn_tutorial: Button = %BtnTutorial
@onready var btn_options: Button = %BtnOptions
@onready var btn_quit: Button = %BtnQuit

func _ready() -> void:
	btn_local.pressed.connect(_on_local_pressed)
	btn_multiplayer.pressed.connect(_on_multiplayer_pressed)
	btn_tutorial.pressed.connect(_on_tutorial_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

func _on_local_pressed() -> void:
	print("[MainMenu] Opening local setup...")
	local_selected.emit()

func _on_multiplayer_pressed() -> void:
	print("[MainMenu] Opening multiplayer menu...")
	multiplayer_selected.emit()

func _on_tutorial_pressed() -> void:
	print("[MainMenu] Tutorial prototype selected...")
	tutorial_selected.emit()

func _on_options_pressed() -> void:
	print("[MainMenu] Opening options...")
	options_selected.emit()

func _on_quit_pressed() -> void:
	print("[MainMenu] Quitting game...")
	quit_selected.emit()
	get_tree().quit()

