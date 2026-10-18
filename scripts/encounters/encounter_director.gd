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

func setup(level: LevelData, actor: Node3D) -> void:
	data = level
	player = actor
	config = data.encounter.duplicate(true) as EncounterConfig
	random.seed = config.seed_value
	timeline.setup(config)
	var errors := config.errors()
	if not errors.is_empty():
		timeline.running = false
		diagnostics = "\n".join(errors)

func nav_for(monster: MonsterDefinition) -> EncounterNavigation:
	var key := "%s/%.2f/%.2f" % [monster.movement, monster.body_radius, monster.body_height]
	if not navigation.has(key):
		var nav := EncounterNavigation.new()
		nav.build(data, monster)
		navigation[key] = nav
	return navigation[key]

func invalidate_navigation() -> void:
	navigation.clear()
	for actor in actors:
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
	actors = actors.filter(func(actor: MonsterActor): return is_instance_valid(actor))
	path_clock += delta
	if path_clock >= 0.1 and not actors.is_empty():
		path_clock = 0
		for i in mini(4, actors.size()):
			path_cursor %= actors.size()
			actors[path_cursor].repath()
			path_cursor += 1
	retry_left -= delta
	var events := timeline.advance(delta * time_scale, is_exploring(), control_ready)
	for event in events:
		if timeline.boss_spawned:
			break
		if event == "regular":
			_spawn_regular()
		elif event.begins_with("elite_") and retry_left <= 0:
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
	var amount := random.randi_range(config.count_min, config.count_max)
	last_regular_positions.clear()
	var choices: Array[Dictionary] = []
	var total := 0.0
	for rule in config.monster_pool:
		if not bool(rule.get("enabled", true)) or float(rule.get("weight", 1)) <= 0:
			continue
		var monster := config.definition_for(str(rule.path), rule)
		var nav := nav_for(monster)
		var candidates := nav.candidates(player.global_position, config.radius_min,
			config.radius_max, monster, _occupied())
		if not candidates.is_empty():
			total += float(rule.get("weight", 1))
			choices.append({"monster": monster, "nav": nav, "weight": float(rule.get("weight", 1))})
	for i in amount:
		if choices.is_empty():
			skipped += 1
			diagnostics = "圆环内无适配生态、探索区域且可达的合法点"
			continue
		var roll := random.randf() * total
		var choice: Dictionary = choices.back()
		for option in choices:
			roll -= float(option.weight)
			if roll <= 0:
				choice = option
				break
		var actor := _spawn(choice.monster, choice.nav, -1)
		if actor != null:
			last_regular_positions.append(actor.global_position)
		else:
			skipped += 1

func _spawn(monster: MonsterDefinition, nav: EncounterNavigation, elite: int) -> MonsterActor:
	var candidates := nav.candidates(player.global_position, config.radius_min,
		config.radius_max, monster, _occupied())
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
		add_child(actor)
		actor.setup(monster, player, nav, elite, config)
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
	return "探索计时 %02d:%02d · %s · 敌人 %d · 跳过 %d\n精英1 %s / 精英2 %s%s" % [
		int(timeline.elapsed) / 60, int(timeline.elapsed) % 60,
		"累计中" if is_exploring() else "静止区暂停", actors.size(), skipped,
		_elite_label(timeline.elites[0]), _elite_label(timeline.elites[1]),
		"\n浓雾安全半径 %.1fm" % fog.radius if is_instance_valid(fog) else ""]

func _elite_label(value: int) -> String:
	return ["未出现", "待生成", "存活", "玩家击杀", "环境死亡"][value]
