extends Node3D

const DEFAULT_LEVEL := "res://data/levels/acceptance_map.tres"
var data: LevelData
var builder: TerrainBuilder
var player: CharacterBody3D
var camera_rig: FollowCameraRig
var camera: Camera3D
var spawn_position: Vector3
var testing := false
var test_direction := Vector3.ZERO
var lower_part_id := "demon_dog_leg"
static var _runtime_font_cache: Font
var climb_enabled := false
var jump_requested := false
var focused_prop: GameplayProp
var interaction_label: Label
var feedback_label: Label
var feedback_until := 0
var climbing := false
var climb_target := Vector3.ZERO
var climb_prop: GameplayProp
var climb_next_prop: GameplayProp
var climb_moving := false
var climb_attached := false
var climb_input_armed := true
var test_climb_input := Vector2.ZERO
const PLAYER_HALF_HEIGHT := 0.8
const INTERACTION_REACH := 1.7
const CLIMB_WALL_OFFSET := 0.38
const CLIMB_MOVE_SPEED := 3.0
const CLIMB_LINK_TOLERANCE := 0.35
## Set before entering the tree to bypass the editor's playtest request file.
var level_override := ""

func _ready() -> void:
	var request := ConfigFile.new()
	request.load("user://terrain_playtest.cfg")
	var requested := resolve_level_path(request, OS.get_cmdline_user_args())
	if not level_override.is_empty():
		requested = level_override
	testing = "--test-editor-level" in OS.get_cmdline_user_args()
	var source := ResourceLoader.load(requested, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if source == null:
		push_error("无法加载关卡：" + requested)
		get_tree().quit(2)
		return
	data = source.fork_for_edit()
	data.ensure_layout()
	if not data.is_surface_exposed(data.spawn_cell, data.spawn_layer):
		push_error("关卡缺少外露的玩家出生点")
		get_tree().quit(2)
		return
	builder = TerrainBuilder.new()
	builder.show_grid = false
	builder.build_collision = true
	builder.level_data = data
	add_child(builder)
	builder.rebuild()
	_setup_interaction_course()
	_connect_props()
	_setup_player()
	LimbField.scatter_ahead(self, spawn_position)
	_setup_camera()
	_setup_ui(requested)
	if testing:
		run_physics_checks.call_deferred()

static func resolve_level_path(request: ConfigFile, args: PackedStringArray) -> String:
	var requested: String = request.get_value("playtest", "level_path",
		request.get_value("playtest", "level", DEFAULT_LEVEL))
	for arg in args:
		if arg.begins_with("--level="):
			requested = arg.trim_prefix("--level=")
	return requested

func _setup_camera() -> void:
	camera_rig = FollowCameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = player
	camera_rig.target_path = NodePath("../Player")
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera_rig.add_child(camera)
	add_child(camera_rig)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#121722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b8c0d6")
	environment.ambient_light_energy = 0.75
	var grade: Resource = load("res://data/color_grade_profile.tres")
	if grade != null:
		grade.apply(environment)
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
	player.name = "Player"
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
	spawn_position = data.world_center(data.spawn_cell, data.spawn_layer) + Vector3(0, 0.82, 0)
	player.position = spawn_position

func _setup_ui(path: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(18, 18)
	label.text = "地形编辑器试玩 · " + path.get_file().get_basename() \
		+ "\nWASD / 方向键移动　Space 跳跃　E 交互 / 脱离　J 破坏　R 回到出生点"
	label.add_theme_font_override("font", runtime_font())
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)
	var ability := CheckButton.new()
	ability.text = "攀爬能力（C）"
	ability.position = Vector2(18, 76)
	ability.add_theme_font_override("font", runtime_font())
	ability.button_pressed = climb_enabled
	ability.toggled.connect(func(enabled: bool): climb_enabled = enabled)
	layer.add_child(ability)
	ability.set_meta("climb_toggle", true)
	var lower_choice := OptionButton.new()
	lower_choice.position = Vector2(210, 80)
	lower_choice.add_theme_font_override("font", runtime_font())
	for lower in PartCatalog.lowers():
		lower_choice.add_item(lower.display_name)
		lower_choice.set_item_metadata(lower_choice.item_count - 1, lower.id)
		if lower.id == lower_part_id:
			lower_choice.select(lower_choice.item_count - 1)
	lower_choice.item_selected.connect(func(index: int):
		lower_part_id = str(lower_choice.get_item_metadata(index)))
	layer.add_child(lower_choice)
	interaction_label = Label.new()
	interaction_label.position = Vector2(18, 122)
	interaction_label.add_theme_font_override("font", runtime_font())
	interaction_label.add_theme_font_size_override("font_size", 21)
	layer.add_child(interaction_label)
	feedback_label = Label.new()
	feedback_label.position = Vector2(18, 156)
	feedback_label.add_theme_font_override("font", runtime_font())
	layer.add_child(feedback_label)

func _connect_props() -> void:
	for node in builder.generated.get_children():
		if node is GameplayProp:
			node.broken.connect(_prop_broken)
			node.opened.connect(func(_prop: Node3D, _actor: Node3D): _feedback("宝箱已打开"))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE:
			if climbing:
				_end_climb(true)
			else:
				jump_requested = true
		KEY_E:
			attempt_interact()
		KEY_J:
			attempt_damage()
		KEY_R:
			reset_player()
		KEY_C:
			climb_enabled = not climb_enabled
			for child in get_children():
				if child is CanvasLayer:
					for control in child.get_children():
						if control.has_meta("climb_toggle"):
							control.set_pressed_no_signal(climb_enabled)

func _feedback(text: String) -> void:
	if feedback_label != null:
		feedback_label.text = text
	feedback_until = Time.get_ticks_msec() + 2500

func _nearest_prop(for_damage := false) -> GameplayProp:
	var nearest: GameplayProp
	var closest := INTERACTION_REACH
	for node in get_tree().get_nodes_in_group("gameplay_props"):
		if not node is GameplayProp or node.state == "broken" or not builder.is_ancestor_of(node):
			continue
		if node.definition.behaviour == PlaceableDefinition.Behaviour.ROCK:
			continue
		if for_damage and node.definition.behaviour != PlaceableDefinition.Behaviour.BREAKABLE:
			continue
		var area := _interaction_shape(node)
		if area == null:
			continue
		var half: Vector3 = area.shape.size * 0.5
		var point := area.to_global(area.to_local(player.global_position).clamp(-half, half))
		var distance := player.global_position.distance_to(point)
		if distance >= closest:
			continue
		# A nearby chest behind a solid wall cannot be used through that wall.
		var query := PhysicsRayQueryParameters3D.create(player.global_position,
			point, 1, [player.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not node.is_ancestor_of(hit["collider"]):
			# Wall attachments use their host's collision.
			var normal: Vector3 = node.global_basis.z.normalized()
			if node.definition.carrier != PlaceableDefinition.Carrier.WALL \
					or Vector3(hit["position"]).distance_to(point) > 0.12 \
					or (player.global_position - node.global_position).dot(normal) < 0:
				continue
		closest = distance
		nearest = node
	return nearest

## Older generated scenes saved the shape under an automatic name, so match by type.
static func _interaction_shape(prop: Node) -> CollisionShape3D:
	var area := prop.get_node_or_null("InteractionArea")
	if area == null:
		return null
	for child in area.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child
	return null

func attempt_interact() -> bool:
	if climbing:
		_end_climb(false)
		return true
	focused_prop = _nearest_prop()
	if focused_prop == null:
		return false
	if focused_prop.definition.behaviour == PlaceableDefinition.Behaviour.CLIMBABLE:
		return begin_climb(focused_prop)
	return focused_prop.interact(player)

func attempt_damage() -> bool:
	if climbing:
		return false
	focused_prop = _nearest_prop(true)
	return focused_prop.apply_damage(1) if focused_prop != null else false

func begin_climb(prop: GameplayProp) -> bool:
	if not climb_enabled:
		_feedback("需要攀爬能力；可用 C 开关验证")
		return false
	var record := ObjectRules.find_record(data, prop.instance_id)
	if record.is_empty():
		return false
	var normal := prop.global_basis.z.normalized()
	if (player.global_position - prop.global_position).dot(normal) < 0:
		return false
	climb_target = _climb_position(prop)
	if not _player_space_clear(climb_target):
		_feedback("攀爬面前没有足够空间")
		return false
	climbing = true
	climb_prop = prop
	climb_next_prop = null
	climb_moving = true
	climb_attached = false
	climb_input_armed = false
	jump_requested = false
	player.velocity = Vector3.ZERO
	_feedback("已附着攀爬面；WASD 移动，E 脱离，Space 跳离")
	return true

func request_climb_move(direction: Vector2i) -> bool:
	if not climbing or not climb_attached or climb_moving or not is_instance_valid(climb_prop):
		return false
	var next: GameplayProp = _adjacent_climb_surface(climb_prop, direction)
	if next == null:
		_feedback("该方向没有可攀爬面")
		return false
	var target: Vector3 = _climb_position(next)
	if not _player_space_clear(target):
		_feedback("目标攀爬面前没有足够空间")
		return false
	climb_next_prop = next
	climb_target = target
	climb_moving = true
	return true

func _adjacent_climb_surface(current: GameplayProp, direction: Vector2i) -> GameplayProp:
	var normal: Vector3 = current.global_basis.z.normalized()
	var tangent: Vector3 = current.global_basis.x.normalized()
	var current_center: Vector3 = _climb_surface_center(current)
	var nearest: GameplayProp
	var nearest_error: float = INF
	for node in get_tree().get_nodes_in_group("climb_surfaces"):
		if not node is GameplayProp or node == current or node.state == "broken" \
				or not builder.is_ancestor_of(node):
			continue
		var candidate_normal: Vector3 = node.global_basis.z.normalized()
		if normal.dot(candidate_normal) < 0.99:
			continue
		var delta: Vector3 = _climb_surface_center(node) - current_center
		if absf(delta.dot(normal)) > 0.12:
			continue
		var lateral: float = delta.dot(tangent)
		var vertical: float = delta.y
		var forward_distance: float
		var cross_distance: float
		if direction.x != 0:
			forward_distance = lateral * direction.x
			cross_distance = absf(vertical)
		else:
			forward_distance = vertical * -direction.y
			cross_distance = absf(lateral)
		if absf(forward_distance - LevelData.CELL_SIZE) > CLIMB_LINK_TOLERANCE \
				or cross_distance > CLIMB_LINK_TOLERANCE:
			continue
		var error: float = absf(forward_distance - LevelData.CELL_SIZE) + cross_distance
		if error < nearest_error:
			nearest_error = error
			nearest = node
	return nearest

static func _climb_surface_center(prop: GameplayProp) -> Vector3:
	var shape: CollisionShape3D = _interaction_shape(prop)
	return shape.global_position if shape != null else prop.global_position

static func _climb_position(prop: GameplayProp) -> Vector3:
	return _climb_surface_center(prop) + prop.global_basis.z.normalized() * CLIMB_WALL_OFFSET

func _player_space_clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (player.get_child(0) as CollisionShape3D).shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	query.margin = 0.01
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _step_climb(delta: float) -> void:
	if not is_instance_valid(climb_prop) or climb_prop.state == "broken" or not climb_enabled:
		_end_climb(false)
		return
	if climb_moving and climb_next_prop != null and (
			not is_instance_valid(climb_next_prop) or climb_next_prop.state == "broken"):
		_end_climb(false)
		return
	player.velocity = Vector3.ZERO
	if interaction_label != null:
		interaction_label.text = "WASD / 方向键攀爬　E 脱离　Space 跳离"
	if climb_moving:
		var motion: Vector3 = (climb_target - player.position).limit_length(CLIMB_MOVE_SPEED * delta)
		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision != null:
			climb_moving = false
			if climb_attached and is_instance_valid(climb_prop):
				player.position = _climb_position(climb_prop)
				climb_next_prop = null
			else:
				_end_climb(false)
			_feedback("攀爬路线受阻")
		elif player.position.distance_to(climb_target) < 0.025:
			player.position = climb_target
			climb_moving = false
			climb_attached = true
			if is_instance_valid(climb_next_prop):
				climb_prop = climb_next_prop
			climb_next_prop = null
		return
	var axis: Vector2 = test_climb_input if testing else Input.get_vector(
		"move_left", "move_right", "move_up", "move_down")
	if axis.length() < 0.25:
		climb_input_armed = true
		return
	if not climb_input_armed:
		return
	climb_input_armed = false
	var direction := Vector2i.ZERO
	if absf(axis.x) > absf(axis.y):
		direction.x = 1 if axis.x > 0 else -1
	else:
		direction.y = 1 if axis.y > 0 else -1
	request_climb_move(direction)

func _end_climb(jump_away: bool) -> void:
	if not climbing:
		return
	var normal := climb_prop.global_basis.z.normalized() if is_instance_valid(climb_prop) else Vector3.ZERO
	climbing = false
	climb_moving = false
	climb_attached = false
	climb_input_armed = true
	climb_prop = null
	climb_next_prop = null
	jump_requested = false
	player.velocity = normal * (3.2 if jump_away else 0.8)
	if jump_away:
		player.velocity.y = 6.0
		_feedback("已跳离攀爬面")
	else:
		_feedback("已脱离攀爬面")

func _prop_broken(prop: Node3D) -> void:
	var before := {}
	for record in data.objects:
		before[str(record["id"])] = true
	ObjectRules.remove_with_dependents(data, [str(prop.get_meta("object_id", ""))])
	for record in data.objects:
		before.erase(str(record["id"]))
	for node in builder.generated.get_children():
		if before.has(str(node.get_meta("object_id", ""))):
			if node is GameplayProp:
				node.set_state("broken")
			node.queue_free()
	_feedback("岩石已破坏" if before.size() == 1 else "岩石已破坏，支撑的物件与附件已清除")

static func runtime_font() -> Font:
	if _runtime_font_cache != null:
		return _runtime_font_cache
	var paths := PackedStringArray([
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
		"C:/Windows/Fonts/msyh.ttc",
		"C:/Windows/Fonts/simhei.ttf",
		"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
		"/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
	])
	for font_path in paths:
		if not FileAccess.file_exists(font_path):
			continue
		var font := FontFile.new()
		font.data = FileAccess.get_file_as_bytes(font_path)
		if font.has_char("地".unicode_at(0)):
			_runtime_font_cache = font
			return font
	_runtime_font_cache = ThemeDB.fallback_font
	return _runtime_font_cache

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if climbing:
		_step_climb(delta)
		return
	var axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := camera.global_basis.z
	forward.y = 0
	var right := camera.global_basis.x
	right.y = 0
	var direction := (right.normalized() * axis.x + forward.normalized() * axis.y).limit_length()
	if testing:
		direction = test_direction
	var feet := player.global_position - Vector3.UP * PLAYER_HALF_HEIGHT
	var block := data.world_to_block(feet + Vector3.UP * 0.04)
	var cell := Vector2i(block.x, block.z)
	var water_layer := block.y
	if not data.is_water_layer(cell, water_layer) and data.is_water_layer(cell, water_layer - 1) \
			and absf(feet.y - data.surface_y(water_layer - 1)) < 0.2:
		water_layer -= 1
	var wet := data.is_water_layer(cell, water_layer)
	var ecosystem := "ocean" if wet else ObjectRules.ecosystem_at(data, cell, block.y - 1)
	var underwater := wet and not data.is_surface_exposed(cell, water_layer) \
		or wet and feet.y < data.surface_y(water_layer) - 0.15
	var effects := SceneMechanism.effects_at(player.global_position)
	var speed := TerrainMovementRules.speed(lower_part_id, ecosystem, underwater)
	if testing and not wet:
		speed = 4.2
	player.velocity.x = direction.x * speed * float(effects.speed_multiplier) + effects.drift.x
	player.velocity.z = direction.z * speed * float(effects.speed_multiplier) + effects.drift.z
	if player.is_on_floor():
		player.velocity.y = 10.2 if jump_requested else -0.1
	else:
		player.velocity.y -= 20.0 * delta
	if wet and lower_part_id == "goose_foot":
		var surface := SceneProbe.water_surface_y(feet)
		if surface > -INF:
			player.velocity.y = clampf((surface + PLAYER_HALF_HEIGHT - player.position.y) * 12, -3, 5)
	elif wet and lower_part_id in ["fish_tail", "water_snake", "octopus_leg"]:
		player.velocity.y = ((1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_CTRL) else 0.0)) * speed + effects.drift.y
		player.set_meta("scene_oxygen", minf(100.0, float(player.get_meta(
			"scene_oxygen", 100.0)) + effects.oxygen * delta))
	jump_requested = false
	player.move_and_slide()
	if player.has_meta("scene_feedback"):
		_feedback(str(player.get_meta("scene_feedback")))
		player.remove_meta("scene_feedback")
	if player.position.y < -4.0:
		reset_player()
	if not testing:
		focused_prop = _nearest_prop()
		if interaction_label != null:
			interaction_label.text = focused_prop.interaction_text() if focused_prop != null else ""
			if focused_prop != null and focused_prop.definition.behaviour == PlaceableDefinition.Behaviour.CLIMBABLE:
				interaction_label.text = "E 攀爬" if climb_enabled else "E 攀爬 · 需要攀爬能力"
		if feedback_label != null and Time.get_ticks_msec() > feedback_until:
			feedback_label.text = ""

func reset_player() -> void:
	climbing = false
	climb_moving = false
	climb_attached = false
	climb_input_armed = true
	climb_prop = null
	climb_next_prop = null
	jump_requested = false
	player.position = spawn_position
	player.velocity = Vector3.ZERO

func run_physics_checks() -> void:
	await get_tree().physics_frame
	var failures: Array[String] = []
	# Acceptance map stairs point north (negative Z).
	var tests := [
		["stair_0_2", data.world_center(Vector2i(7, 11)) + Vector3(0, 0.82, 0),
			Vector3(0, 0, -1), 170, data.surface_y(1)],
		["stair_2_4", data.world_center(Vector2i(7, 7)) + Vector3(0, 0.82, 0),
			Vector3(0, 0, -1), 170, data.surface_y(2)],
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
	var blocked := player.position.y < data.world_center(Vector2i(3, 10)).y + 1.2
	print("EDITOR CHECK cliff_block ", blocked)
	if not blocked:
		failures.append("cliff_block")
	print("EDITOR LEVEL TEST FAILURES: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


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
	prop.collision_layer = 0
	prop.collision_mask = 0


func _paint_cells(cells: Array[Vector2i], zone_tags: PackedStringArray, tint: Color) -> void:
	for cell in cells:
		if not data.cell_exists(cell) or data.stair_at(cell) >= 0:
			continue
		var zone := SurfaceZone.new()
		zone.position = data.world_center(cell) + Vector3(0.0, 0.4, 0.0)
		add_child(zone)
		zone.setup(Vector3(LevelData.CELL_SIZE, 1.0, LevelData.CELL_SIZE), zone_tags, tint)
