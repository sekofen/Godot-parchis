extends SceneTree
## Actual models, shared lighting and camera: overview plus moving close-ups.
const Unit := preload("res://src/pieces/PieceVisual.gd")
const Lore := preload("res://Factions.gd")
func _initialize() -> void: call_deferred("_capture")
func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/previews"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b111c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a4bdd9")
	environment.ambient_light_energy = .65
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-35,0)
	light.light_energy = 1.6
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.position = Vector3(0,3.5,6)
	camera.look_at(Vector3(0,.5,0))
	var units: Array[Node3D] = []
	var labels: Array[Label3D] = []
	for team in range(4):
		var unit := Unit.new()
		stage.add_child(unit)
		unit.position.x = (team-1.5)*1.3
		unit.build(team,team,Lore.profile(team).color)
		unit.set_process(false)
		unit.heading = -.25
		unit._process(.2)
		units.append(unit)
		var label := Label3D.new()
		label.text = ["VANGUARD\nSentinel","ACCORD\nSeed warden","CONTINUUM\nPrism drone","CORSAIRS\nSkimmer"][team]
		label.position = Vector3(unit.position.x,-.25,.15)
		label.font_size = 32
		label.pixel_size = .003
		label.modulate = Lore.profile(team).color.lightened(.4)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(label)
		labels.append(label)
	await _save(viewport,"units-lineup")
	if "--motion" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/previews/.unit-motion"))
		for frame in range(96):
			for unit in units:
				unit.moving = frame >= 24 and frame < 72
				unit.heading = -.25 if frame < 48 else .5
				if frame == 8: unit.acknowledge()
				if frame == 24: unit.play_launch()
				if frame == 72: unit.play_arrival()
				unit._process(1.0/24)
			await _save(viewport,".unit-motion/frame-%04d" % frame)
	for team in range(4):
		camera.size = 1.65
		var center := units[team].position + Vector3(0,.55,0)
		camera.position = center + Vector3(1.4,.9,2)
		camera.look_at(center)
		for other in units: other.visible = other == units[team]
		for label in labels: label.visible = label == labels[team]
		await _save(viewport,"unit-%d-idle" % team)
		units[team].moving = true
		for step in range(10): units[team]._process(.04)
		await _save(viewport,"unit-%d-travel" % team)
	# Review all sixteen actual models with consistent light and framing.
	for unit in units: unit.visible = false
	for label in labels: label.visible = false
	viewport.size = Vector2i(1600,1400)
	camera.size = 7.1
	camera.position = Vector3(0,5.9,10)
	camera.look_at(Vector3(0,2.8,0))
	for team in range(4):
		for slot in range(4):
			var unit := Unit.new()
			stage.add_child(unit)
			unit.position = Vector3((slot-1.5)*1.55,(3-team)*1.65,0)
			unit.build(team,slot,Lore.profile(team).color)
			unit.set_process(false)
			unit.heading = -.3
			unit._process(.2)
			var label := Label3D.new()
			label.text = "%s · %02d\n%s" % [Lore.profile(team).short_name.to_upper(),slot+1,unit.get_meta("callsign")]
			label.position = unit.position + Vector3(0,-.21,.1)
			label.font_size = 26
			label.pixel_size = .0032
			label.modulate = Lore.profile(team).color.lightened(.4)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			stage.add_child(label)
	await _save(viewport,"units-all-crews")
	print("Saved faction unit lineup, all 16 crew variants and close-up idle/travel frames")
	quit()
func _save(viewport: SubViewport, label: String) -> void:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://artifacts/previews/"+label+".png")
