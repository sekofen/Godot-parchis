extends Control
## Readable, constant-size screen targets above the 3D board. Actual GUI buttons
## provide click/keyboard hit targets; leader lines preserve the exact landing cell.
signal picked(id: String)
var camera: Camera3D
var bounds := Rect2()
var pins: Array[Dictionary] = []
var route: Array[Vector3] = []
var _lines: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_pins(items: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	pins.clear()
	for item in items:
		var button := Button.new()
		button.name = item.id
		button.text = item.text
		button.add_theme_font_size_override("font_size", 20)
		button.custom_minimum_size = Vector2(48, 38)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = item.get("tooltip", "")
		var style := StyleBoxFlat.new()
		style.bg_color = Color("102d3a") if item.kind == "pawn" else Color("b9ff75")
		style.border_color = item.color
		style.set_border_width_all(2)
		style.set_corner_radius_all(7)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color("34536b") if item.kind == "pawn" else Color("e1ffc0")
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_color_override("font_color", Color("ffffff") if item.kind == "pawn" else Color("10210c"))
		button.add_theme_color_override("font_hover_color", Color("ffffff") if item.kind == "pawn" else Color("10210c"))
		add_child(button)
		button.size = button.get_combined_minimum_size()
		button.pressed.connect(func(): picked.emit(item.id))
		var pin: Dictionary = item.duplicate()
		pin.button = button
		pins.append(pin)
	update_positions()

func _process(_delta: float) -> void:
	update_positions()

func update_positions() -> void:
	if not is_instance_valid(camera):
		return
	_lines.clear()
	var occupied: Array[Rect2] = []
	for pin in pins:
		var button: Button = pin.button
		var point := camera.unproject_position(pin.world)
		button.visible = bounds.has_point(point) and not camera.is_position_behind(pin.world)
		if not button.visible:
			continue
		var rect := Rect2(point - Vector2(button.size.x * 0.5, button.size.y + 15), button.size)
		var origin := rect.position
		var offsets: Array[Vector2] = [Vector2.ZERO]
		for row in range(1, 5):
			offsets.append(Vector2(0, -row * (button.size.y + 7)))
			offsets.append(Vector2(0, row * (button.size.y + 7)))
			offsets.append(Vector2(row * (button.size.x + 7), 0))
			offsets.append(Vector2(-row * (button.size.x + 7), 0))
		for offset in offsets:
			var candidate := Rect2(origin + offset, rect.size)
			candidate.position.x = clampf(candidate.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - candidate.size.x))
			candidate.position.y = clampf(candidate.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - candidate.size.y))
			var collision := false
			for other in occupied:
				if candidate.grow(4).intersects(other):
					collision = true
					break
			rect = candidate
			if not collision:
				break

		button.position = rect.position
		occupied.append(rect)
		_lines.append([point, Vector2(rect.get_center().x, rect.end.y), pin.color])
	queue_redraw()

func _draw() -> void:
	if is_instance_valid(camera) and route.size() > 1:
		for index in range(1, route.size()):
			var start := camera.unproject_position(route[index - 1])
			var end := camera.unproject_position(route[index])
			draw_dashed_line(start, end, Color(0.72, 1, 0.46, 0.65), 3, 6)
	for line in _lines:
		draw_line(line[0], line[1], Color("07121d"), 5, true)
		draw_line(line[0], line[1], line[2], 2, true)
		draw_circle(line[0], 4, line[2])
