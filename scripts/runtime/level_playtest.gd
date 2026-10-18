extends Node3D

const MovementConfig := preload("res://scripts/movement_table.gd")
const MonsterTable := preload("res://scripts/monsters/monster_table.gd")
const FieldMonster := preload("res://scripts/monsters/field_monster.gd")

# 正常启动进入包含宝箱、可推岩石、可破坏岩石与攀爬面的完整交互样例。
# acceptance_map.tres 保留为阶梯和悬崖的纯地形自动化夹具。
const DEFAULT_LEVEL := "res://data/levels/art_acceptance.tres"
const PLAYER_SCENE := preload("res://scenes/player.tscn")
var data: LevelData
var builder: TerrainBuilder
var player: CharacterBody3D
var camera_rig: FollowCameraRig
var camera: Camera3D
var spawn_position: Vector3
var testing := false
var test_direction := Vector3.ZERO
static var _runtime_font_cache: Font
var climb_enabled := false
var jump_requested := false
var focused_prop: GameplayProp
var interaction_label: Label
var feedback_label: Label
var feedback_until := 0
var _key_help: ColorRect
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
	if not data.cell_exists(data.spawn_cell):
		push_error("关卡缺少有效的玩家出生点")
		get_tree().quit(2)
		return
	builder = TerrainBuilder.new()
	builder.show_grid = false
	builder.build_collision = true
	builder.level_data = data
	add_child(builder)
	builder.rebuild()
	# 地图里已经摆了宝箱、岩石、风化岩和攀岩点时，直接用这些物件。
	# 色块和白盒只补给没有玩法物件的旧地图。
	if not _has_authored_gameplay():
		_setup_interaction_course()
	_connect_props()
	_setup_player()
	_setup_camera()
	_setup_ui(requested)
	_setup_bag()
	_spawn_field_monsters()
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
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	if player == null:
		push_error("无法实例化肢体角色：res://scenes/player.tscn")
		get_tree().quit(2)
		return
	player.name = "Player"
	player.floor_snap_length = 0.4
	player.floor_max_angle = deg_to_rad(50.0)
	add_child(player)
	player.add_to_group("level_player")
	# PlayerController 的原点在脚底；保留少量离地量，避免出生首帧嵌入顶面。
	spawn_position = data.world_center(data.spawn_cell, data.spawn_layer) + Vector3(0, 0.08, 0)
	player.position = spawn_position
	if player is PlayerController:
		(player as PlayerController).respawn_position = spawn_position

func _setup_ui(path: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(18, 18)
	label.text = "地形编辑器试玩 · " + path.get_file().get_basename() \
		+ "\n按 Q 查看按键"
	label.add_theme_font_override("font", runtime_font())
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)
	# 自动化仍可直接设置 climb_enabled；正式试玩由当前上肢能力决定，不再占用 C。
	if not player is PlayerController:
		var ability := CheckButton.new()
		ability.text = "攀爬能力（C）"
		ability.position = Vector2(18, 76)
		ability.add_theme_font_override("font", runtime_font())
		ability.button_pressed = climb_enabled
		ability.toggled.connect(func(enabled: bool): climb_enabled = enabled)
		layer.add_child(ability)
		ability.set_meta("climb_toggle", true)
	interaction_label = Label.new()
	interaction_label.position = Vector2(18, 148)
	interaction_label.add_theme_font_override("font", runtime_font())
	interaction_label.add_theme_font_size_override("font_size", 21)
	layer.add_child(interaction_label)
	feedback_label = Label.new()
	feedback_label.position = Vector2(18, 182)
	feedback_label.add_theme_font_override("font", runtime_font())
	layer.add_child(feedback_label)
	_build_key_help(layer)


func _build_key_help(layer: CanvasLayer) -> void:
	var dim := ColorRect.new()
	dim.name = "KeyHelp"
	dim.visible = false
	dim.color = Color(0.05, 0.035, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var card := Label.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -560.0
	card.offset_top = -380.0
	card.offset_right = 560.0
	card.offset_bottom = 380.0
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_theme_font_override("font", runtime_font())
	card.add_theme_font_size_override("font_size", 28)
	card.add_theme_color_override("font_color", Color(0.97, 0.91, 0.8))
	card.text = "\n".join([
		"按键",
		"",
		"W A S D / 方向键    移动",
		"W / S    攀着的时候上下爬",
		"Space    跳跃、起飞、滑翔；靠近可爬面时抓住",
		"E    开宝箱、开始攀爬、从攀爬面脱离",
		"G    捡肢体，推、拉、砸、挖",
		"J    攻击",
		"R    回到出生点",
		"Z    切换上肢",
		"X    切换下肢",
		"T    开关突破",
		"C    身上没有肢体时，切换旧拼接",
		"Tab    打开或关闭背包",
		"1    属性页",
		"2    培养页",
		"Esc    关闭菜单，或关闭这份说明",
		"鼠标拖拽    装配、放进培养皿、拖到回收箱",
		"右键    回收肢体",
		"Q    打开或关闭这份说明",
	])
	dim.add_child(card)
	_key_help = dim

func _setup_bag() -> void:
	var menu := (load("res://scenes/stitch_menu.tscn") as PackedScene).instantiate()
	menu.name = "StitchMenu"
	add_child(menu)


func _spawn_field_monsters() -> void:
	# 自动化把关卡当成子场景实例化，不能在出生点旁边刷出会追人的怪。
	if get_tree() == null or get_tree().current_scene != self:
		return
	var spots: Array[Vector3] = []
	for x in data.map_size.x:
		for z in data.map_size.y:
			var cell := Vector2i(x, z)
			if not data.cell_exists(cell) or cell.distance_to(data.spawn_cell) < 4:
				continue
			spots.append(data.world_center(cell))
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return spawn_position.distance_squared_to(a) > spawn_position.distance_squared_to(b))
	var cursor := 0
	for monster_id in MonsterTable.ids():
		var entry := MonsterTable.monster(monster_id)
		var pack := maxi(int(entry.get("pack", 1)), 1)
		for _member in pack:
			if cursor >= spots.size():
				return
			var monster := FieldMonster.new() as CharacterBody3D
			monster.call("setup", monster_id, spots[cursor] + Vector3(0.0, 0.15, 0.0))
			add_child(monster)
			cursor += 1


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
			elif not player is PlayerController:
				jump_requested = true
		KEY_E:
			attempt_interact()
		KEY_J:
			if not player is PlayerController:
				attempt_damage()
		KEY_R:
			reset_player()
		KEY_Q:
			_key_help.visible = not _key_help.visible
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _key_help.visible:
				_key_help.visible = false
				get_viewport().set_input_as_handled()
		KEY_C:
			if not player is PlayerController:
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
		# 从躯干射向交互体中心。贴地的最近点会先打到地块顶面，宝箱和岩石就永远够不着。
		var origin := player.global_position + Vector3.UP * 0.85
		var center := area.global_position
		var query := PhysicsRayQueryParameters3D.create(origin, center, 1, [player.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not node.is_ancestor_of(hit["collider"]):
			var hit_position := Vector3(hit["position"])
			var remaining := hit_position.distance_to(center)
			# 抓点没有自己的实体碰撞，射线会停在它所贴的侧壁上。
			if remaining > 0.25:
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
	if not _has_climb_ability():
		_feedback("当前上肢没有攀爬能力")
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
	if player is PlayerController:
		player.set_physics_process(false)
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

func _screen_wall_tangent(prop: GameplayProp) -> Vector3:
	var tangent := prop.global_basis.x.normalized()
	var screen_right := Vector3.RIGHT
	if camera_rig != null:
		screen_right = camera_rig.get_planar_axes()[0]
	if tangent.dot(screen_right) < 0.0:
		tangent = -tangent
	return tangent


func _adjacent_climb_surface(current: GameplayProp, direction: Vector2i) -> GameplayProp:
	var normal: Vector3 = current.global_basis.z.normalized()
	var tangent: Vector3 = _screen_wall_tangent(current)
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

func _climb_position(prop: GameplayProp) -> Vector3:
	return _climb_surface_center(prop) + prop.global_basis.z.normalized() * _climb_wall_offset() \
		- Vector3.UP * _player_collision_center_offset() + Vector3.UP * 0.08


func _player_collision_center_offset() -> float:
	var collision := player.get_node_or_null("Collision") as CollisionShape3D
	if collision != null:
		return collision.position.y
	return 0.0


func _climb_wall_offset() -> float:
	var collision := player.get_node_or_null("Collision") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		return (collision.shape as CapsuleShape3D).radius + 0.06
	return CLIMB_WALL_OFFSET

func _player_space_clear(point: Vector3) -> bool:
	var collision := player.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		for child in player.get_children():
			if child is CollisionShape3D:
				collision = child
				break
	if collision == null or collision.shape == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * _player_collision_center_offset())
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	query.margin = 0.01
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _step_climb(delta: float) -> void:
	if not is_instance_valid(climb_prop) or climb_prop.state == "broken" or not _has_climb_ability():
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
		var motion: Vector3 = (climb_target - player.position).limit_length(MovementConfig.number("part", "surface_climb_speed", 3.0) * delta)
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
	var direction := Vector2i.ZERO
	if absf(axis.x) > absf(axis.y):
		direction.x = 1 if axis.x > 0 else -1
	else:
		direction.y = 1 if axis.y > 0 else -1
	var next := _adjacent_climb_surface(climb_prop, direction)
	if next != null:
		if not climb_input_armed:
			return
		climb_input_armed = false
		var target := _climb_position(next)
		if not _player_space_clear(target):
			_feedback("目标攀爬面前没有足够空间")
			return
		climb_next_prop = next
		climb_target = target
		climb_moving = true
		return
	_slide_on_wall(delta, axis)

func _slide_on_wall(delta: float, axis: Vector2) -> void:
	var tangent := _screen_wall_tangent(climb_prop)
	var wish := tangent * axis.x + Vector3.UP * -axis.y
	if wish.length_squared() < 0.01:
		return
	var proposed: Vector3 = player.position + wish.normalized() * MovementConfig.number("part", "surface_climb_speed", 3.0) * delta
	if not _climb_slide_allowed(climb_prop, proposed):
		if -axis.y > 0.5 and _try_mount_from_climb(climb_prop):
			return
		return
	player.position = _stick_climb_point(climb_prop, proposed)
	player.velocity = Vector3.ZERO


func _stick_climb_point(prop: GameplayProp, feet: Vector3) -> Vector3:
	var normal := prop.global_basis.z.normalized()
	var center := _climb_surface_center(prop)
	var on_plane := feet - normal * (feet - center).dot(normal)
	return on_plane + normal * _climb_wall_offset()


func _climb_slide_allowed(prop: GameplayProp, feet: Vector3) -> bool:
	var record := ObjectRules.find_record(data, prop.instance_id)
	var normal := prop.global_basis.z.normalized()
	var center := _climb_surface_center(prop)
	if absf((feet - center).dot(normal)) > 1.2:
		return false
	if str(record.get("anchor_kind", "")) != "wall":
		return _inside_climb_shape(prop, feet)
	var direction := int(record.get("wall_direction", -1))
	var layer := int(record.get("anchor_layer", -1))
	if direction < 0 or layer < 0:
		return _inside_climb_shape(prop, feet)
	var inward := feet - normal * (LevelData.CELL_SIZE * 0.5)
	var cell := data.world_to_cell(inward)
	if not _exposed_wall_face(cell, layer, direction):
		return false
	var bottom := 0.0 if layer == 0 else data.surface_y(layer - 1)
	return feet.y >= bottom - 0.05 and feet.y <= data.surface_y(layer) - 0.2


func _exposed_wall_face(cell: Vector2i, layer: int, direction: int) -> bool:
	if direction < 0 or direction > 3 or not data.in_bounds(cell):
		return false
	if not data.layer_exists(cell, layer) or data.stair_at(cell) >= 0:
		return false
	return not data.layer_exists(cell + LevelData.DIRS[direction], layer)


func _inside_climb_shape(prop: GameplayProp, feet: Vector3) -> bool:
	var shape := _interaction_shape(prop)
	if shape == null or not shape.shape is BoxShape3D:
		return false
	var local := shape.to_local(feet)
	var half := (shape.shape as BoxShape3D).size * 0.5
	return absf(local.x) <= half.x + 0.08 and absf(local.y) <= half.y + 0.08


func _try_mount_from_climb(prop: GameplayProp) -> bool:
	var record := ObjectRules.find_record(data, prop.instance_id)
	if str(record.get("anchor_kind", "")) != "wall":
		return false
	var direction := int(record.get("wall_direction", -1))
	var layer := int(record.get("anchor_layer", -1))
	if direction < 0 or layer < 0:
		return false
	var normal := prop.global_basis.z.normalized()
	var high := data.world_to_cell(player.position - normal * (LevelData.CELL_SIZE * 0.5))
	if not _exposed_wall_face(high, layer, direction):
		return false
	var stand := data.world_center(high) + Vector3(0.0, 0.08, 0.0)
	if player.position.y < stand.y - 0.45 or not _player_space_clear(stand):
		return false
	_end_climb(false)
	player.velocity = Vector3.ZERO
	player.position = stand
	_feedback("爬上去了")
	return true


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
	if player is PlayerController:
		player.set_physics_process(not testing)
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
	if player is PlayerController and not testing:
		_update_interaction_ui()
		if player.position.y < -4.0:
			reset_player()
		return
	if player is PlayerController and player.is_physics_processing():
		# 物理验收通过 test_direction 驱动同一个角色，但只能有一个移动循环。
		player.set_physics_process(false)
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
		player.velocity.y = 10.2 if jump_requested else -0.1
	else:
		player.velocity.y -= 20.0 * delta
	jump_requested = false
	player.move_and_slide()
	if player.position.y < -4.0:
		reset_player()
	if not testing:
		_update_interaction_ui()


func _update_interaction_ui() -> void:
	focused_prop = _nearest_prop()
	if interaction_label != null:
		interaction_label.text = focused_prop.interaction_text() if focused_prop != null else ""
		if focused_prop != null and focused_prop.definition.behaviour == PlaceableDefinition.Behaviour.CLIMBABLE:
			interaction_label.text = "E 攀爬" if _has_climb_ability() else "E 攀爬 · 当前上肢不可攀爬"
	if feedback_label != null and Time.get_ticks_msec() > feedback_until:
		feedback_label.text = ""


func _has_climb_ability() -> bool:
	if climb_enabled:
		return true
	var controller := player as PlayerController
	if controller == null or controller.parts == null:
		return false
	return controller.parts.current_upper().has_ability("grab_climb", controller.parts.breakthrough)

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
	if player is PlayerController:
		player.set_physics_process(not testing)

func run_physics_checks() -> void:
	await get_tree().physics_frame
	var failures: Array[String] = []
	# Acceptance map stairs point north (negative Z).
	var tests := [
		["stair_0_2", data.world_center(Vector2i(7, 11)) + Vector3(0, 0.08, 0),
			Vector3(0, 0, -1), 170, data.surface_y(1)],
		["stair_2_4", data.world_center(Vector2i(7, 7)) + Vector3(0, 0.08, 0),
			Vector3(0, 0, -1), 170, data.surface_y(2)],
	]
	for spec in tests:
		player.position = spec[1]
		player.velocity = Vector3.ZERO
		test_direction = spec[2]
		for frame in spec[3]:
			await get_tree().physics_frame
		var foot := player.position.y
		var passed := absf(foot - float(spec[4])) < 0.2
		print("EDITOR CHECK ", spec[0], " ", passed, " foot=", foot, " position=", player.position)
		if not passed:
			failures.append(spec[0])
	# A plain +2m face must block a player with no stair.
	player.position = data.world_center(Vector2i(3, 10)) + Vector3(0, 0.08, 0)
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


func _has_authored_gameplay() -> bool:
	for record in data.objects:
		var definition := ObjectRules.definition(record)
		if definition != null and definition.behaviour != PlaceableDefinition.Behaviour.DECORATION:
			return true
	return false


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
