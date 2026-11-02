extends SceneTree
## Shared assertions, isolated game setup and real viewport input.
var checks := 0
var failed := false

func _initialize() -> void:
	call_deferred("_start_isolated")

func _start_isolated() -> void:
	# Tests never depend on the user's saved language and never change it on disk.
	TranslationServer.set_locale("en")
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAILED: " + description)
		quit(1)
		assert(condition, description)

func load_game(parent: Node = root) -> Node3D:
	var game_scene := load("res://MainGame.tscn").instantiate() as Node3D
	game_scene.remember_guidance = false
	game_scene.remember_audio_settings = false
	parent.add_child(game_scene)
	# Most integration tests need sound events, not active audio playback.
	game_scene.audio.enabled = false
	game_scene._rng.seed = 8291
	game_scene.dice_stage.throw_rng.seed = 17
	return game_scene

func click(button: Button) -> void:
	await process_frame
	dispatch_click(button)
	await process_frame

func dispatch_click(button: Button) -> void:
	# Route through GUI hit testing so overlapping controls can expose regressions.
	check(is_instance_valid(button) and button.is_visible_in_tree(), "Click target is visible")
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)

func finish(description: String) -> void:
	# Let queued frees and pending callbacks complete before engine shutdown.
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	if not failed:
		print("PASS: %d checks: %s" % [checks, description])
	quit(1 if failed else 0)
