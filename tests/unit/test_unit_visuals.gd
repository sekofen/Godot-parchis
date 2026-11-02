extends "res://tests/support/test_case.gd"
const Unit := preload("res://src/pieces/PieceVisual.gd")
const Lore := preload("res://Factions.gd")
func _run() -> void:
	for team in range(4):
		var unit := Unit.new()
		root.add_child(unit)
		unit.build(team,0,Lore.profile(team).color)
		unit.set_process(false)
		unit.position = Vector3(4,0,7)
		unit.face_destination(unit.position+Vector3.RIGHT)
		check(is_equal_approx(unit.heading,PI*.5),"Models face the actual route")
		for step in range(20): unit._process(.05)
		var idle := unit.rig.transform
		unit.moving = true
		for step in range(20): unit._process(.05)
		check(unit.activity > .99,"Travel pose blends in")
		check(unit.rig.transform != idle,"Travel has a faction-specific body pose")
		check(unit.position == Vector3(4,0,7),"Animation never changes the logical board position")
		unit.moving = false
		unit.play_arrival()
		check(unit.arrival == 1,"Landing triggers a settling impulse")
		for step in range(30): unit._process(.05)
		check(is_zero_approx(unit.activity) and is_zero_approx(unit.arrival),"Movement and landing settle without permanent offsets")
		check(absf(angle_difference(unit.rig.rotation.y,PI*.5)) < .001,"Route heading converges")
		unit.queue_free()
		await process_frame
	# Every crew slot has reproducible geometry and its own rig/animation personality.
	for team in range(4):
		var silhouettes: Array[String] = []
		var names: Array[String] = []
		var cadences: Array[float] = []
		for slot in range(4):
			var unit := Unit.new()
			root.add_child(unit)
			unit.build(team,slot,Lore.profile(team).color)
			unit.set_process(false)
			var signature := geometry_signature(unit.rig)
			check(signature not in silhouettes,"Crew variants have different geometry")
			silhouettes.append(signature)
			check(str(unit.get_meta("callsign")) not in names,"Crew identities are unique within faction")
			names.append(str(unit.get_meta("callsign")))
			check(unit.cadence not in cadences,"Crew members have different motion cadence")
			cadences.append(unit.cadence)
			if team < 2:
				check(unit.knees.size() == 2 and unit.elbows.size() == 2,"Walkers have independent knees and elbows")
				check(unit.knees[0].get_parent() == unit.limbs[0],"Knees inherit the hip transform")
				unit.moving = true
				var bent := false
				for frame in range(40):
					unit._process(.025)
					bent = bent or absf(unit.knees[0].rotation.x) > .1
				check(bent,"Knee actually bends during gait")
			unit.play_launch()
			unit.acknowledge()
			unit._process(.05)
			check(unit.launch > 0 and unit.attention > 0,"Launch and selection responses are active")
			unit.moving = false
			for frame in range(200): unit._process(.02)
			check(is_zero_approx(unit.launch) and is_zero_approx(unit.attention),"Responses return to idle")
			unit.build((team+1)%4,slot,Lore.profile((team+1)%4).color)
			unit._process(.1)
			unit.build(team,slot,Lore.profile(team).color)
			check(geometry_signature(unit.rig) == signature,"Rebuilding across factions reproduces geometry")
			check(unit.get_child_count() == 1 and not unit.moving and is_zero_approx(unit.activity),"Rebuild resets animation and removes old rig")
			unit.queue_free()
			await process_frame
	await finish("unit motion, route orientation, crew variants, rebuilds and fixed board positions")

func geometry_signature(node: Node3D) -> String:
	var result := str(node.transform)
	if node is MeshInstance3D:
		result += str(node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D: result += geometry_signature(child)
	return result
