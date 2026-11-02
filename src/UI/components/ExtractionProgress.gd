extends HBoxContainer
## Extraction progress indicator showing docked crew lights.
@onready var lights: Array[Panel] = [$Slot0, $Slot1, $Slot2, $Slot3]
@onready var count_label: Label = $CountLabel
var _finished := 0

func set_progress(finished: int, color: Color) -> void:
	_finished = finished
	_refresh_text()
	for slot in range(4):
		var style := StyleBoxFlat.new()
		style.bg_color = color if slot < finished else Color("102332")
		style.border_color = color
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		lights[slot].add_theme_stylebox_override("panel", style)
	count_label.add_theme_color_override("font_color", color)

func _refresh_text() -> void:
	for light in lights:
		light.tooltip_text = tr("PROGRESS_TOOLTIP") % _finished
	count_label.text = tr("PROGRESS_COUNT") % _finished

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
