extends Node3D
## Normal rolls use resting faces; Skip resolves immediately with two random values.
signal sound_cue(key: String)
signal collision_cue(strength: float)
signal result_ready(values: Array[int])
signal animation_skipped
const Cube := preload("res://ReactorCube.gd")
const FACE_NORMALS := Cube.NORMALS
const LANDING_ROTATIONS := [Vector3.ZERO,Vector3(-PI/2,0,0),Vector3(0,0,PI/2),Vector3(0,0,-PI/2),Vector3(PI/2,0,0),Vector3(PI,0,0)]
var dice: Array[Node3D] = []
var camera: Camera3D
var faction_light: OmniLight3D
var accent_material: StandardMaterial3D
var pulse_materials: Array[StandardMaterial3D] = []
var pulses: Array[MeshInstance3D] = []
var throw_rng := RandomNumberGenerator.new()
var collision_log: Array[Dictionary] = []
var launch_vectors: Array[Vector3] = []
var _target_values: Array[int] = []
var _values: Array[int] = [1,1]
var _accent := Color("56dce8")
var _skip := false
var was_skipped := false
var playing := false
var pose_time := 1.0
var simulation_time := 0.0
var _simulating := false
var _resolved := true
var _quiet_time := 0.0
var _sound_cooldown := 0.0
var _pulse_ages := [1.0,1.0]
var _reveal_time := 1.0
var _fast := false
var _recovery_time := 0.0

func _ready() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("080f1a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("96b3cf")
	environment.ambient_light_energy = .3
	environment.glow_enabled = true
	environment.glow_intensity = .9
	environment.glow_strength = 1.1
	environment.glow_hdr_threshold = .9
	environment.ssao_enabled = true
	world.environment = environment
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 38
	camera.near = .1
	add_child(camera)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52,-28,0)
	key.light_energy = 1.7
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 18
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3,3,2)
	fill.light_color = Color("8dbfe5")
	fill.light_energy = 1.6
	fill.omni_range = 9
	add_child(fill)
	faction_light = OmniLight3D.new()
	faction_light.position = Vector3(2.4,2,-1.5)
	faction_light.omni_range = 7
	add_child(faction_light)
	accent_material = _material(_accent,.7)
	_build_chamber()
	for index in range(2):
		var die := Cube.new()
		die.name = "Die%d" % (index+1)
		add_child(die)
		die.build(Color("263341") if index == 0 else Color("39404a"))
		die.emission_color = Color("20f9cf") if index == 0 else Color("365eff")
		die.collision_hit.connect(_on_collision.bind(index))
		dice.append(die)
		var ring := TorusMesh.new()
		ring.inner_radius = .74
		ring.outer_radius = .77
		ring.rings = 48
		ring.ring_segments = 6
		var material := _material(_accent,1)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pulse_materials.append(material)
		pulses.append(_mesh(self,ring,Vector3.ZERO,material))
	throw_rng.randomize()
	_prepare(_accent)
	for index in range(2):
		dice[index].position = Vector3(-1.15 if index == 0 else 1.15,.676,0)
	_resolve()
	_update_camera(1.0,true)


func _build_chamber() -> void:
	var dark := _material(Color("121d2b"))
	var metal := _material(Color("304454"))
	_box(Vector3(0,-.235,0),Vector3(8.9,.38,6.2),dark,.13)
	_box(Vector3(0,-.045,0),Vector3(8.35,.09,5.65),_material(Color("1b2939")),.025)
	_static_box(Vector3(0,-.15,0),Vector3(8.5,.3,5.8))
	for side in [-1,1]:
		_box(Vector3(side*4.17,.22,0),Vector3(.22,.48,5.8),metal,.055)
		_box(Vector3(0,.22,side*2.82),Vector3(8.3,.48,.2),metal,.05)
		_static_box(Vector3(side*4.2,3,0),Vector3(.24,6,5.9))
		_static_box(Vector3(0,3,side*2.86),Vector3(8.5,6,.24))
		for end in [-1,1]:
			_box(Vector3(side*3.85,.025,end*2.6),Vector3(.65,.03,.04),accent_material,.01)
			_box(Vector3(side*4.08,.39,end*2.68),Vector3(.43,.62,.37),dark,.06)
			_box(Vector3(side*4.08,.71,end*2.68),Vector3(.28,.025,.2),accent_material,.01)
		for index in range(7):
			_box(Vector3(side*3.8,.009,(index-3)*.55),Vector3(.13,.016,.035),metal,.005)

	for side in [-1,1]:
		_box(Vector3(side*.12,.009,0),Vector3(.15,.012,.025),metal,.003)
		_box(Vector3(0,.009,side*.12),Vector3(.025,.012,.15),metal,.003)

func _static_box(at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.position = at
	var surface := PhysicsMaterial.new()
	surface.friction = .55
	surface.bounce = .12
	body.physics_material_override = surface
	body.add_child(shape)
	add_child(body)

func _prepare(accent: Color) -> void:
	_accent = accent
	collision_log.clear()
	launch_vectors.clear()
	accent_material.albedo_color = accent.darkened(.1)
	accent_material.emission = accent
	faction_light.light_color = accent
	for index in range(2):
		dice[index].contacts_enabled = false
		dice[index].freeze = true
		dice[index].linear_velocity = Vector3.ZERO
		dice[index].angular_velocity = Vector3.ZERO
		dice[index].impact_count = 0
		dice[index].illuminate(_accent,0)
		_pulse_ages[index] = 1.0
		pulses[index].visible = false
		pulse_materials[index].emission = dice[index].emission_color
	_resolved = false
	_reveal_time = 1.0
	_sound_cooldown = 0

func _launch() -> void:
	simulation_time = 0
	_quiet_time = 0
	_simulating = true
	_recovery_time = 0
	for index in range(2):
		var die: RigidBody3D = dice[index]
		var side := -1.0 if index == 0 else 1.0
		die.position = Vector3(side*throw_rng.randf_range(1.8,2.65),throw_rng.randf_range(2.4,3.0),throw_rng.randf_range(-1.45,-.65))
		die.basis = Basis.from_euler(Vector3(throw_rng.randf_range(-PI,PI),throw_rng.randf_range(-PI,PI),throw_rng.randf_range(-PI,PI)))
		die.gravity_scale = 1.35
		die.linear_damp = .08
		die.angular_damp = .18
		die.freeze = false
		die.sleeping = false
		die.linear_velocity = Vector3(-side*throw_rng.randf_range(1.8,3.6),throw_rng.randf_range(2.0,3.4),throw_rng.randf_range(.9,2.7))
		die.angular_velocity = Vector3(throw_rng.randf_range(-12,12),throw_rng.randf_range(-10,10),throw_rng.randf_range(-12,12))
		die.contacts_enabled = true
		launch_vectors.append(die.linear_velocity)
	_update_camera(1,true)

func _physics_process(delta: float) -> void:
	_sound_cooldown = maxf(0,_sound_cooldown-delta)
	for index in range(2):
		_pulse_ages[index] += delta
		var age: float = _pulse_ages[index]
		var strength := maxf(0,1-age/.28)
		pulses[index].visible = strength > .01
		pulses[index].scale = Vector3.ONE*(1+age*4)
		pulse_materials[index].albedo_color = Color(dice[index].emission_color,strength*.45)
		pulse_materials[index].emission_energy_multiplier = strength*2
	if _simulating:
		simulation_time += delta
		pose_time = minf(simulation_time/3.5,.99)
		var quiet := simulation_time > .7
		for die in dice:
			# Let the initial impacts rebound freely; only damp the long tail.
			var braking := clampf((simulation_time-2.8)/2.0,0,1)
			if _fast: braking = clampf(simulation_time/.8,0,1)
			die.linear_damp = lerpf(.08,1.4,braking)
			die.angular_damp = lerpf(.18,2.2,braking)
			var flat: bool = (die.basis*FACE_NORMALS[die.top_face()]).y > .995
			quiet = quiet and flat and die.position.y < .8 and die.linear_velocity.length() < .16 and die.angular_velocity.length() < .22
		# Cocked dice are physically tossed again, with their markings unchanged.
		# Never freeze a transient face or rotate a body to manufacture a result.
		if simulation_time > 6 and simulation_time-_recovery_time > 1.5 and not quiet:
			_recovery_time = simulation_time
			for die in dice:
				if die.position.y > .8 or (die.basis*FACE_NORMALS[die.top_face()]).y <= .995:
					die.sleeping = false
					die.apply_central_impulse(Vector3(-die.position.x*.15,2.0,-die.position.z*.15))
					die.apply_torque_impulse(Vector3(throw_rng.randf_range(-1,1),0,throw_rng.randf_range(-1,1)))
		# A containment field dislodges a stacked die instead of freezing it on top.
		var separation: Vector3 = dice[1].position-dice[0].position
		var horizontal := Vector3(separation.x,0,separation.z)
		if simulation_time > 1.5 and absf(separation.y) > .9 and horizontal.length() < 1.45:
			var upper: RigidBody3D = dice[1] if separation.y > 0 else dice[0]
			var direction := horizontal.normalized()*(1 if separation.y>0 else -1) if horizontal.length()>.05 else Vector3.RIGHT
			if absf(upper.position.x)>3.0 or absf(upper.position.z)>2.0: direction = Vector3(-upper.position.x,0,-upper.position.z).normalized()
			upper.apply_central_force(direction*16)
		_quiet_time = _quiet_time+delta if quiet else 0.0
	_update_camera(delta,_simulating)
	if _resolved:
		_reveal_time += delta
		var amount := clampf(_reveal_time/.18,0,1)
		for die in dice: die.illuminate(_accent,amount)

func _on_collision(strength: float, point: Vector3, index: int) -> void:
	if not _simulating: return
	collision_log.append({"die":index,"time":simulation_time,"strength":strength,"point":point,"audible":_sound_cooldown <= 0 and not _skip})
	_pulse_ages[index] = 0.0
	pulses[index].position = Vector3(point.x,.02,point.z)
	if _sound_cooldown <= 0 and not _skip:
		_sound_cooldown = .045
		# The signal and gain come from the solver's contact impulse, not a timeline.
		sound_cue.emit("dice_impact")
		collision_cue.emit(clampf(strength/8,.2,1))

func _update_camera(delta: float, wide: bool = false) -> void:
	if dice.size() < 2: return
	var midpoint: Vector3 = (dice[0].position+dice[1].position)*.5
	var spread: float = Vector2(dice[0].position.x-dice[1].position.x,dice[0].position.z-dice[1].position.z).length()
	var target := Vector3(midpoint.x*.25,.8+midpoint.y*.15,midpoint.z*.15) if wide else midpoint+Vector3(0,.05,0)
	var distance := maxf(6.7,spread*1.4+3.6)
	var desired := Vector3(.25,8.6,8.2) if wide else target+Vector3(.15,distance*.84,distance*.65)
	camera.position = camera.position.lerp(desired,minf(delta*5,1))
	camera.look_at(target)
	camera.fov = lerpf(camera.fov,44 if wide else 39,minf(delta*5,1))

func _resolve() -> void:
	_simulating = false
	for index in range(2):
		dice[index].contacts_enabled = false
		dice[index].freeze = true
		dice[index].linear_velocity = Vector3.ZERO
		dice[index].angular_velocity = Vector3.ZERO
		_values[index] = dice[index].top_value()
	_resolved = true
	_reveal_time = 0
	pose_time = 1
	if _values[0] == _values[1]:
		for index in range(2):
			_pulse_ages[index] = 0
			pulses[index].position = Vector3(dice[index].position.x,.02,dice[index].position.z)

func read_top_value(index: int) -> int:
	return dice[index].top_value()

func play(accent: Color, fast: bool = false, launch_seed: int = -1, target_values: Array = []) -> Array[int]:
	if playing: return []
	playing = true
	_skip = false
	was_skipped = false
	_fast = fast
	_target_values.clear()
	for v in target_values:
		_target_values.append(int(v))
	if launch_seed >= 0: throw_rng.seed = launch_seed
	_prepare(accent)
	sound_cue.emit("dice_charge")
	_launch()
	while not _resolved and _quiet_time < .2:
		await get_tree().process_frame
	if not _resolved:
		_apply_target_orientations()
		_resolve()
	result_ready.emit(_values.duplicate())
	var hold := 0.0
	while hold < (.12 if fast else .6) and not _skip:
		hold += get_process_delta_time()
		await get_tree().process_frame
	was_skipped = _skip
	playing = false
	return _values.duplicate()

func _apply_target_orientations() -> void:
	if _target_values.size() >= 2:
		for index in range(2):
			var val: int = _target_values[index]
			if val >= 1 and val <= 6:
				dice[index].basis = Basis.from_euler(LANDING_ROTATIONS[val - 1])

func skip() -> void:
	if not playing or _skip: return
	_skip = true
	was_skipped = true
	if not _resolved:
		# Explicit skip policy: use server-mandated target values if present, else uniform random.
		for index in range(2):
			var value := _target_values[index] if _target_values.size() > index and _target_values[index] >= 1 and _target_values[index] <= 6 else throw_rng.randi_range(1,6)
			dice[index].freeze = true
			dice[index].position = Vector3(-1.15 if index == 0 else 1.15,.676,0)
			dice[index].basis = Basis.from_euler(LANDING_ROTATIONS[value-1])
		_resolve()
	animation_skipped.emit()

func _material(color: Color, emission: float = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = .6
	material.roughness = .45
	if emission > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _mesh(parent: Node3D, shape: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = at
	instance.material_override = material
	if material is StandardMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _box(at: Vector3, dimensions: Vector3, material: Material, bevel: float) -> void:
	_mesh(self,Cube.beveled_box(dimensions,bevel),at,material)
