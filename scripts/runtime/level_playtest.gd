extends Node3D

const DEFAULT_LEVEL := "res://data/levels/acceptance_map.tres"
var data: LevelData
var builder: TerrainBuilder
var player: CharacterBody3D
var camera: Camera3D
var spawn_position: Vector3
var testing := false
var test_direction := Vector3.ZERO

func _ready() -> void:
	var requested := ProjectSettings.get_setting("terrain_editor/playtest_level", DEFAULT_LEVEL) as String
	var request := ConfigFile.new()
	if request.load("user://terrain_playtest.cfg") == OK:
		requested = request.get_value("playtest", "level", requested)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			requested = arg.trim_prefix("--level=")
	testing = "--test-editor-level" in OS.get_cmdline_user_args()
	data = load(requested) as LevelData
	if data == null:
		push_error("无法加载关卡：" + requested)
		get_tree().quit(2)
		return
	builder = TerrainBuilder.new()
	builder.show_grid = false
	builder.build_collision = true
	builder.level_data = data
	add_child(builder)
	builder.rebuild()
	_setup_camera()
	_setup_player()
	_setup_ui(requested)
	if testing:
		run_physics_checks.call_deferred()

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var profile := load("res://data/art_profile.tres") as ArtProfile
	camera.size = profile.orthographic_size
	camera.position = profile.camera_offset
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#121722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b8c0d6")
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.floor_snap_length = 0.4
	player.floor_max_angle = deg_to_rad(50)
	add_child(player)
	player.add_to_group("level_player")
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.6
	shape.radius = 0.32
	collision.shape = shape
	player.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 1.6
	mesh.radius = 0.32
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffc875")
	visual.material_override = material
	player.add_child(visual)
	spawn_position = data.world_center(data.spawn_cell) + Vector3(0, 0.82, 0)
	player.position = spawn_position

func _setup_ui(path: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(18, 18)
	label.text = "地形编辑器试玩\nWASD / 方向键移动　R 重置\n" + path
	# Use Godot/system font fallback; no unlicensed local font is required.
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := camera.global_basis.z
	forward.y = 0
	var right := camera.global_basis.x
	right.y = 0
	var direction := (right.normalized() * axis.x + forward.normalized() * axis.y).limit_length()
	if testing:
		direction = test_direction
	player.velocity.x = direction.x * 4.2
	player.velocity.z = direction.z * 4.2
	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= 20.0 * delta
	player.move_and_slide()
	if player.position.y < -4.0 or Input.is_physical_key_pressed(KEY_R):
		reset_player()

func reset_player() -> void:
	player.position = spawn_position
	player.velocity = Vector3.ZERO

func run_physics_checks() -> void:
	await get_tree().physics_frame
	var failures: Array[String] = []
	# Acceptance map stairs point north (negative Z).
	var tests := [
		["stair_0_2", data.world_center(Vector2i(7, 11)) + Vector3(0, 0.82, 0),
			Vector3(0, 0, -1), 170, 2.0],
		["stair_2_4", data.world_center(Vector2i(7, 7)) + Vector3(0, 2.82, 0),
			Vector3(0, 0, -1), 170, 4.0],
	]
	for spec in tests:
		player.position = spec[1]
		player.velocity = Vector3.ZERO
		test_direction = spec[2]
		for frame in spec[3]:
			await get_tree().physics_frame
		var foot := player.position.y - 0.8
		var passed := absf(foot - float(spec[4])) < 0.2
		print("EDITOR CHECK ", spec[0], " ", passed, " foot=", foot)
		if not passed:
			failures.append(spec[0])
	# A plain +2m face must block a player with no stair.
	player.position = data.world_center(Vector2i(3, 10)) + Vector3(0, 0.82, 0)
	player.velocity = Vector3.ZERO
	test_direction = Vector3(0, 0, -1)
	for frame in 65:
		await get_tree().physics_frame
	var blocked := player.position.y < 1.2
	print("EDITOR CHECK cliff_block ", blocked)
	if not blocked:
		failures.append("cliff_block")
	print("EDITOR LEVEL TEST FAILURES: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
