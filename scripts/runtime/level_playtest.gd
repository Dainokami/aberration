extends Node3D

const DEFAULT_LEVEL := "res://data/levels/acceptance_map.tres"
const PLAYER_SCENE := "res://scenes/player.tscn"

var data: LevelData
var builder: TerrainBuilder
var player: PlayerController
var spawn_position: Vector3
var testing := false


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
	_setup_interaction_course()
	_setup_player()
	_setup_camera()
	_setup_world()
	_setup_ui(requested)
	if testing:
		run_physics_checks.call_deferred()


func _setup_interaction_course() -> void:
	var fluid: Array[Vector2i] = [Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 13), Vector2i(12, 14), Vector2i(13, 14)]
	var desert: Array[Vector2i] = [Vector2i(12, 10), Vector2i(13, 10)]
	_paint_cells(fluid, PackedStringArray(["fluid"]), Color(0.35, 0.72, 0.95, 0.45))
	_paint_cells(desert, PackedStringArray(["desert", "hard"]), Color(0.93, 0.76, 0.38, 0.5))
	var pool := Vector2i(13, 14)
	if not data.cell_exists(pool) or data.stair_at(pool) >= 0:
		return
	var prop := AffordanceProp.new()
	prop.kind = "destructible_soft"
	prop.box_size = Vector3(0.7, 0.45, 0.7)
	prop.max_health = 22
	prop.position = data.world_center(pool)
	add_child(prop)


func _paint_cells(cells: Array[Vector2i], zone_tags: PackedStringArray, tint: Color) -> void:
	for cell in cells:
		if not data.cell_exists(cell) or data.stair_at(cell) >= 0:
			continue
		var zone := SurfaceZone.new()
		zone.position = data.world_center(cell) + Vector3(0.0, 0.4, 0.0)
		add_child(zone)
		zone.setup(Vector3(LevelData.CELL_SIZE, 1.0, LevelData.CELL_SIZE), zone_tags, tint)


func _setup_player() -> void:
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	player.name = "Player"
	player.add_to_group("level_player")
	spawn_position = data.world_center(data.spawn_cell) + Vector3(0.0, 0.08, 0.0)
	player.position = spawn_position
	player.set_meta("playtest_level", "")
	add_child(player)
	LimbField.scatter_ahead(self, spawn_position)


func _setup_camera() -> void:
	var rig := FollowCameraRig.new()
	rig.name = "CameraRig"
	rig.target_path = NodePath("../Player")
	add_child(rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 35.0
	camera.near = 0.1
	camera.far = 100.0
	camera.current = true
	rig.add_child(camera)


func _setup_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.67, 0.75, 0.79)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	environment.ambient_light_energy = 0.5
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)


func _setup_ui(path: String) -> void:
	player.set_meta("playtest_level", path)
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	hud.player_path = NodePath("../Player")
	add_child(hud)
	var menu := (load("res://scenes/stitch_menu.tscn") as PackedScene).instantiate()
	menu.name = "StitchMenu"
	add_child(menu)


func _physics_process(_delta: float) -> void:
	if player == null or testing:
		return
	if Input.is_physical_key_pressed(KEY_R):
		player.respawn()


func run_physics_checks() -> void:
	await get_tree().physics_frame
	var failures: Array[String] = []
	var rig := player.get_node_or_null("ArtRoot/PartSockets")
	var uses_character := player is PlayerController and rig != null and not _has_capsule_mesh(player)
	print("EDITOR CHECK playable_character ", uses_character)
	if not uses_character:
		failures.append("playable_character")
	var upper_id := player.parts.current_upper().id if player.parts else ""
	var interactive := player.parts != null and player.parts.handles_attack() and upper_id == "gorilla_arm"
	print("EDITOR CHECK part_interaction ", interactive, " ", upper_id)
	if not interactive:
		failures.append("part_interaction")
	# Acceptance map stairs point north (negative Z). Feet sit on the surface.
	var tests: Array = [
		["stair_0_2", data.world_center(Vector2i(7, 11)), 10.0, 2.0],
		["stair_2_4", data.world_center(Vector2i(7, 7)), 10.0, 4.0],
	]
	for spec in tests:
		await _place(spec[1])
		await _walk_distance(float(spec[2]))
		var foot := player.position.y
		var passed := absf(foot - float(spec[3])) < 0.35
		print("EDITOR CHECK ", spec[0], " ", passed, " foot=", foot)
		if not passed:
			failures.append(str(spec[0]))
	# A plain +2m face must block a player with no stair.
	await _place(data.world_center(Vector2i(3, 10)))
	await _walk_distance(6.0)
	var blocked := player.position.y < 1.2
	print("EDITOR CHECK cliff_block ", blocked, " foot=", player.position.y)
	if not blocked:
		failures.append("cliff_block")
	print("EDITOR LEVEL TEST FAILURES: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _place(surface: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.position = surface + Vector3(0.0, 0.08, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _walk_distance(distance: float) -> void:
	Input.action_press("move_forward")
	var start := player.global_position
	for _frame in 360:
		await get_tree().physics_frame
		var flat := player.global_position - start
		flat.y = 0.0
		if flat.length() >= distance:
			break
	Input.action_release("move_forward")
	await get_tree().physics_frame


func _has_capsule_mesh(body: Node) -> bool:
	for child in body.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node and mesh_node.mesh is CapsuleMesh:
			return true
	return false
