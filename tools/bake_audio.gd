extends SceneTree
const Palette := preload("res://tools/AudioPalette.gd")
func _initialize() -> void:
	for key in Palette.DURATIONS:
		var sound := Palette.render(key)
		var error := sound.save_to_wav("res://assets/audio/%s.wav" % key)
		if error != OK:
			push_error("Cannot bake " + key)
			quit(1)
			return
	print("Baked %d original sound effects" % Palette.DURATIONS.size())
	quit()
