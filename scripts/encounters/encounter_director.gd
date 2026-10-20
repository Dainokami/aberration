class_name EncounterDirector
extends Node3D

signal report(message: String)
var data: LevelData
var config: EncounterConfig
var player: Node3D
var timeline := EncounterTimeline.new()
var random := RandomNumberGenerator.new()
var navigation := {}
var actors: Array[MonsterActor] = []
var gate: BossGate
var fog: ContractingFog
var control_ready := false
var time_scale := 1.0
var retry_left := 0.0
var path_clock := 0.0
var path_cursor := 0
var skipped := 0
var spawn_count := 0
var diagnostics := ""
var last_regular_positions: Array[Vector3] = []
var point_clocks := {}
var automatic_point_radius := 32.0
var radius_clock := 0.0
var stream_builder: TerrainBuilder
var _navigation_center := Vector2i(-99999, -99999)
var pending_points := {}
var _navigation_working_set := -1

func setup(level: LevelData, actor: Node3D) -> void:
	data = level
	player = actor
	if is_inside_tree() and get_parent() != null:
		for node in get_parent().get_children():
			if node is TerrainBuilder and node.level_data == level:
				stream_builder = node
				break
	config = data.encounter.duplicate(true) as EncounterConfig \
		if data.encounter != null else EncounterConfig.default_config()
	point_clocks.clear()
	pending_points.clear()
	navigation.clear()
	random.seed = config.seed_value
	timeline.setup(config)
	_update_point_ranges()
	var errors := config.errors()
	if not errors.is_empty():
		timeline.running = false
		diagnostics = "\n".join(errors)

func nav_for(monster: MonsterDefinition) -> EncounterNavigation:
	var key := "%s/%.2f/%.2f" % [monster.movement, monster.body_radius, monster.body_height]
	if not navigation.has(key):
		var nav := EncounterNavigation.new()
		if is_instance_valid(stream_builder) and stream_builder.is_streaming():
			var records: Array = []
			var seen := {}
			for chunk: Vector2i in stream_builder._chunk_nodes:
				for record in stream_builder._objects_by_chunk.get(chunk, []):
					if not seen.has(record.id):
						seen[record.id] = true
						records.append(record)
			nav.build_incremental(data, monster, stream_builder._chunk_nodes, records)
		else:
			nav.build(data, monster)
		navigation[key] = nav
	return navigation[key]

func invalidate_navigation() -> void:
	navigation.clear()
	for actor in actors:
		if is_instance_valid(actor) and actor.get_meta("stream_sleeping", false) != true:
			actor.navigation = nav_for(actor.definition)

func player_surface() -> Vector3i:
	var feet := player.global_position - Vector3.UP * 0.8
	var block := data.world_to_block(feet + Vector3.UP * 0.02)
	var cell := Vector2i(block.x, block.z)
	var layer := block.y - 1
	if data.is_water_layer(cell, block.y):
		layer = block.y
	if layer < 0 or not data.layer_exists(cell, layer):
		for i in range(data.layer_count(cell) - 1, -1, -1):
			if data.surface_y(i) <= feet.y + 0.2:
				layer = i
				break
	return Vector3i(cell.x, layer, cell.y)

func is_exploring() -> bool:
	var index := player_surface()
	return data.in_bounds(Vector2i(index.x, index.z)) and index.y >= 0 \
		and EncounterRegions.zone(data, Vector2i(index.x, index.z), index.y) == 0

func _physics_process(delta: float) -> void:
	if config == null or not timeline.running or not control_ready:
		return
	_step_navigation()
	actors = actors.filter(func(actor: MonsterActor): return is_instance_valid(actor))
	radius_clock -= delta
	if radius_clock <= 0:
		_update_point_ranges()
		_update_stream_actors()
		if is_instance_valid(stream_builder) and stream_builder.is_streaming():
			for point in data.monster_spawn_points:
				if not point_active(point):
					continue
				for rule in config.monster_pool:
					if not bool(rule.get("enabled", true)):
						continue
					var species := config.ordinary_definition(rule)
					if species != null and species.available() and _point_supports_species(point, species):
						nav_for(species)
		radius_clock = 0.5
	path_clock += delta
	if path_clock >= 0.1 and not actors.is_empty():
		path_clock = 0
		for i in mini(4, actors.size()):
			path_cursor %= actors.size()
			if not bool(actors[path_cursor].get_meta("stream_sleeping", false)):
				actors[path_cursor].repath()
			path_cursor += 1
	retry_left -= delta
	advance_spawn_points(delta * time_scale)
	var events := timeline.advance(delta * time_scale, is_exploring(), control_ready)
	for event in events:
		if timeline.boss_spawned:
			break
		if event.begins_with("elite_") and retry_left <= 0:
			_spawn_elite(event.to_int() if event.is_valid_int() else int(event.trim_prefix("elite_")))
		elif event == "boss" and retry_left <= 0:
			_spawn_gate()
	if retry_left <= 0:
		retry_left = 1.0
	if is_instance_valid(fog):
		fog.step(delta)

func _occupied() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for actor in actors:
		if is_instance_valid(actor):
			result.append(actor.global_position)
	return result

func _spawn_regular() -> void:
	last_regular_positions.clear()
	for point in data.monster_spawn_points:
		if bool(point.get("enabled", true)):
			_spawn_point(point)

func advance_spawn_points(delta: float) -> void:
	if not config.enabled or not control_ready or not timeline.running or timeline.boss_spawned:
		return
	for point in data.monster_spawn_points:
		var id := str(point.id)
		if not bool(point.get("enabled", true)):
			point_clocks.erase(id)
			continue
		if not point_active(point):
			continue
		var clock := float(point_clocks.get(id, 0.0)) + delta
		if clock >= MonsterSpawnPoints.INTERVAL:
			clock = fmod(clock, MonsterSpawnPoints.INTERVAL)
			_spawn_point(point)
		point_clocks[id] = clock

func _step_navigation() -> void:
	var start := Time.get_ticks_usec()
	for nav: EncounterNavigation in navigation.values():
		if nav.building:
			nav.step_build(2000)
		if Time.get_ticks_usec() - start >= 2000:
			break
	for id: String in pending_points.keys():
		var point := MonsterSpawnPoints.find(data, id)
		if point.is_empty() or not point_active(point):
			pending_points.erase(id)
		elif navigation.values().all(func(nav): return not nav.building):
			pending_points.erase(id)
			_spawn_point(point)

func _update_point_ranges() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var focus := player.global_position - Vector3.UP * 0.8
	automatic_point_radius = MonsterSpawnPoints.automatic_radius(data, focus, camera)
	for actor in actors:
		if actor.elite_index < 0 and actor.get_meta("spawn_point_id", "") != "":
			var point := MonsterSpawnPoints.find(data, str(actor.get_meta("spawn_point_id")))
			if not point.is_empty():
				actor.set_spawn_range(MonsterSpawnPoints.center(data, point), point_radius(point))

func point_radius(point: Dictionary) -> float:
	var custom := float(point.get("activation_radius", 0.0))
	return custom if custom > 0 else automatic_point_radius

func point_active(point: Dictionary) -> bool:
	return bool(point.get("enabled", true)) and MonsterSpawnPoints.contains(
		MonsterSpawnPoints.center(data, point), point_radius(point), player.global_position)

func point_alive(id: String) -> int:
	var amount := 0
	for actor in actors:
		if is_instance_valid(actor) and str(actor.get_meta("spawn_point_id", "")) == id:
			amount += 1
	return amount

func _spawn_point(point: Dictionary) -> void:
	if not point_active(point):
		return
	if is_instance_valid(stream_builder) and stream_builder.is_streaming():
		for cell: Vector3i in point.get("cells", []):
			if not stream_builder.stream_cell_loaded(Vector2i(cell.x, cell.z)):
				stream_builder.ensure_stream_position(
					data.world_center(Vector2i(cell.x, cell.z), cell.y), 2.0)
				navigation.clear()
	var vacancy := int(point.get("max_alive", 2)) - point_alive(str(point.id))
	var amount := mini(vacancy, random.randi_range(config.count_min, config.count_max))
	for i in amount:
		var choices: Array[Dictionary] = []
		var total := 0.0
		for rule in config.monster_pool:
			if not bool(rule.get("enabled", true)) or float(rule.get("weight", 1)) <= 0:
				continue
			var monster := config.ordinary_definition(rule)
			if monster == null or not monster.available():
				continue
			if is_instance_valid(stream_builder) and stream_builder.is_streaming() \
					and not _point_supports_species(point, monster):
				continue
			var nav := nav_for(monster)
			if not nav.point_candidates(point, monster, _occupied()).is_empty():
				total += float(rule.get("weight", 1))
				choices.append({"monster": monster, "nav": nav, "weight": float(rule.get("weight", 1))})
		if choices.is_empty():
			if navigation.values().any(func(nav): return nav.building):
				pending_points[str(point.id)] = true
				break
			skipped += 1
			diagnostics = "%s：无适配生态或空闲落脚格，请检查怪池、禁刷与障碍" % point.get("name", "刷新点")
			break
		var roll := random.randf() * total
		var choice: Dictionary = choices.back()
		for option in choices:
			roll -= float(option.weight)
			if roll <= 0:
				choice = option
				break
		var actor := _spawn(choice.monster, choice.nav, -1, point)
		if actor != null:
			last_regular_positions.append(actor.global_position)
		else:
			skipped += 1

func _point_supports_species(point: Dictionary, monster: MonsterDefinition) -> bool:
	for ecology in MonsterSpawnPoints.ecosystems(data, point):
		if ecology in monster.ecosystems:
			return true
	return false

func _update_stream_actors() -> void:
	if not is_instance_valid(stream_builder) or not stream_builder.is_streaming():
		return
	var center := TerrainChunkStream.chunk_for(data.world_to_cell(player.global_position))
	var moved := center.distance_squared_to(_navigation_center) >= 4
	var stream := stream_builder.chunk_stream
	var working_set := stream.loaded_total + stream.unloaded_total
	if stream.pending.is_empty() and not is_instance_valid(stream.job_root) \
			and working_set != _navigation_working_set:
		_navigation_working_set = working_set
		moved = true
	if moved:
		_navigation_center = center
		navigation.clear()
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var far := (actor.spawn_radius < 0 or not actor.player_in_spawn_range()) and (
			actor.global_position.distance_to(player.global_position) > 96.0 \
			or not stream_builder.chunk_stream.retained.has(
				TerrainChunkStream.chunk_for(data.world_to_cell(actor.global_position))))
		var sleeping := bool(actor.get_meta("stream_sleeping", false))
		if far:
			if not sleeping:
				actor.windup_left = -1
				actor.visual.cancel_attack()
				actor.path.clear()
				actor.navigation = null
				actor.set_physics_process(false)
				actor.collision_layer = 0
				actor.set_meta("stream_sleeping", true)
			continue
		stream_builder.ensure_stream_position(actor.global_position, 3.0)
		if actor.returning_home:
			stream_builder.ensure_stream_position(actor.home_position, 3.0)
		if sleeping or moved:
			actor.navigation = nav_for(actor.definition)
			actor.repath()
		if sleeping:
			actor.set_physics_process(true)
			actor.collision_layer = 2
			actor.set_meta("stream_sleeping", false)

func _spawn(monster: MonsterDefinition, nav: EncounterNavigation, elite: int,
		point: Dictionary = {}) -> MonsterActor:
	var candidates := nav.point_candidates(point, monster, _occupied()) if not point.is_empty() \
		else nav.candidates(player.global_position, config.radius_min, config.radius_max, monster, _occupied())
	while not candidates.is_empty():
		var pick := random.randi_range(0, candidates.size() - 1)
		var id := candidates[pick]
		candidates.remove_at(pick)
		var position := nav.graph.get_point_position(id)
		if not _physics_clear(position, monster):
			continue
		var actor := MonsterActor.new()
		actor.position = position
		actor.name = "Monster_%d" % spawn_count
		if not point.is_empty():
			actor.set_meta("spawn_point_id", str(point.id))
		add_child(actor)
		actor.setup(monster, player, nav, elite, config)
		if is_instance_valid(stream_builder) and stream_builder.runtime_lighting != null:
			stream_builder.runtime_lighting.apply(actor.visual)
		if not point.is_empty():
			actor.set_spawn_range(MonsterSpawnPoints.center(data, point), point_radius(point))
		actor.defeated.connect(_defeated)
		actors.append(actor)
		spawn_count += 1
		actor.repath()
		return actor
	return null

func _physics_clear(position: Vector3, monster: MonsterDefinition) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = monster.body_radius
	shape.height = maxf(monster.body_height, shape.radius * 2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = position + Vector3.UP * (shape.height * 0.5 + 0.08)
	query.collision_mask = 3
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _spawn_elite(index: int) -> void:
	var monster := config.elite_definition(index)
	var actor := _spawn(monster, nav_for(monster), index)
	if actor != null:
		timeline.elite_spawned(index)
		report.emit("精英怪%d出现" % (index + 1))
	else:
		diagnostics = "精英怪%d等待合法生成点" % (index + 1)

func _spawn_gate() -> void:
	if is_instance_valid(gate):
		return
	var definition := MonsterDefinition.new()
	definition.body_radius = 0.8
	definition.body_height = 3.5
	var nav := nav_for(definition)
	if nav.building:
		return
	var player_id := nav.nearest_id(player.global_position)
	if player_id < 0:
		diagnostics = "Boss 门等待可达位置"
		return
	var candidates: Array[int] = []
	for id in nav.surfaces:
		if nav.components[id] == nav.components[player_id] \
				and nav.spawn_error(id, null, _occupied()).is_empty() \
				and _physics_clear(nav.graph.get_point_position(id), definition):
			candidates.append(id)
	if candidates.is_empty():
		diagnostics = "Boss 门无合法探索区位置，稍后重试"
		return
	gate = BossGate.new()
	gate.name = "BossGate"
	gate.position = nav.graph.get_point_position(candidates[random.randi_range(0, candidates.size()-1)])
	gate.target_scene = config.boss_scene
	add_child(gate)
	gate.entered.connect(stop)
	timeline.boss_spawned = true
	timeline.boss_pending = false
	fog = ContractingFog.new()
	fog.name = "ContractingFog"
	add_child(fog)
	fog.setup(data, gate.global_position, config, player)
	report.emit("Boss 门出现，浓雾开始收缩")

func _defeated(actor: MonsterActor, cause: String) -> void:
	if actor.elite_index >= 0:
		timeline.elite_died(actor.elite_index, cause)
	if cause == "player":
		for item in actor.definition.drop_items():
			var drop := MonsterDrop.new()
			drop.position = actor.global_position + Vector3.UP * 0.2
			drop.item_id = item
			drop.texture_path = actor.definition.image_path
			add_child(drop)
	actors.erase(actor)
	diagnostics = "%s已%s" % [actor.definition.display_name, "击杀" if cause == "player" else "因环境死亡"]

func attack_nearest() -> bool:
	var best: MonsterActor
	var distance := 2.4
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var d := player.global_position.distance_to(actor.global_position + Vector3.UP * 0.8)
		if d < distance:
			var query := PhysicsRayQueryParameters3D.create(player.global_position,
				actor.global_position + Vector3.UP * 0.8, 1)
			if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				best = actor
				distance = d
	if best == null:
		return false
	best.take_damage(14, "player")
	return true

func interact() -> String:
	if is_instance_valid(gate):
		var message := gate.interact(player)
		if not message.is_empty():
			return message
	for drop in get_tree().get_nodes_in_group("monster_drop"):
		if drop is MonsterDrop and drop.global_position.distance_to(player.global_position) < 2:
			return drop.collect(player)
	return ""

func stop() -> void:
	timeline.running = false
	if is_instance_valid(fog):
		fog.active = false
	for actor in actors:
		if is_instance_valid(actor):
			actor.set_physics_process(false)

func summary() -> String:
	return "探索计时 %02d:%02d · %s · 敌人 %d · 跳过 %d\n普通怪：%d个刷新点 · 范围内每30秒补充\n精英1 %s / 精英2 %s%s" % [
		int(timeline.elapsed) / 60, int(timeline.elapsed) % 60,
		"累计中" if is_exploring() else "静止区暂停", actors.size(), skipped,
		data.monster_spawn_points.size(),
		_elite_label(timeline.elites[0]), _elite_label(timeline.elites[1]),
		"\n浓雾安全半径 %.1fm" % fog.radius if is_instance_valid(fog) else ""]

func _elite_label(value: int) -> String:
	return ["未出现", "待生成", "存活", "玩家击杀", "环境死亡"][value]
