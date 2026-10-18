extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("SPAWN POINT CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func fixture(size := Vector2i(16, 16)) -> LevelData:
	var data := LevelData.new()
	data.setup_blank(size)
	for i in data.columns.size():
		data.columns[i] = {"layers": [{"tile_id": "grass"}]}
	data.spawn_cell = size / 2
	data.spawn_layer = 0
	return data

func run() -> void:
	var map := fixture()
	var point := MonsterSpawnPoints.create("营地")
	check(MonsterSpawnPoints.edit(map, point, Vector3i(2, 0, 2)).is_empty(), "first cell")
	check(not MonsterSpawnPoints.edit(map, point, Vector3i(4, 0, 2)).is_empty(), "reject detached")
	check(MonsterSpawnPoints.edit(map, point, Vector3i(3, 0, 2)).is_empty(), "adjacent cell")
	MonsterSpawnPoints.edit(map, point, Vector3i(4, 0, 2))
	check(not MonsterSpawnPoints.edit(map, point, Vector3i(3, 0, 2), true).is_empty(), "erase cannot split")
	map.monster_spawn_points.append(point)
	check(MonsterSpawnPoints.errors(map).is_empty(), "valid connected group")
	var duplicate := MonsterSpawnPoints.create()
	check(not MonsterSpawnPoints.edit(map, duplicate, Vector3i(2, 0, 2)).is_empty(), "reject overlap")
	var fork := map.fork_for_edit()
	fork.monster_spawn_points[0].cells.erase(Vector3i(4, 0, 2))
	check(map.monster_spawn_points[0].cells.size() == 3, "fork isolated")
	var restored := LevelData.new()
	restored.restore_data(map.clone_data())
	check(restored.monster_spawn_points == map.monster_spawn_points, "snapshot transfer")
	check(ResourceSaver.save(map, "/tmp/spawn-point-roundtrip.tres") == OK, "save resource")
	var loaded := ResourceLoader.load("/tmp/spawn-point-roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.monster_spawn_points == map.monster_spawn_points, "resource reload")
	map.expand_to_include(Rect2i(Vector2i(-2, -2), Vector2i.ONE))
	check(map.monster_spawn_points[0].cells[0] == Vector3i(2, 0, 2), "negative expansion keeps anchors")
	map.set_layer(Vector2i(2, 2), 1, {"tile_id": "rock"})
	MonsterSpawnPoints.prune(map)
	check(map.monster_spawn_points[0].cells.size() == 3, "covered lower point retained")
	map.remove_layer(Vector2i(3, 2), 0)
	MonsterSpawnPoints.prune(map)
	check(map.monster_spawn_points.size() == 2 and MonsterSpawnPoints.errors(map).is_empty(), "terrain removal preserves both valid components")
	var source := fixture(Vector2i(4, 4))
	point = MonsterSpawnPoints.create("双格")
	point.activation_radius = 24.0
	point.cells = [Vector3i(1, 0, 1), Vector3i(2, 0, 1)]
	source.monster_spawn_points.append(point)
	check(not str(LevelPrefab.capture(source, Rect2i(Vector2i.ZERO, Vector2i(2, 4))).error).is_empty(), "capture rejects cut point")
	var prefab: LevelPrefab = LevelPrefab.capture(source, source.map_bounds()).prefab
	var target := fixture()
	var result := prefab.stamp(target, Vector2i(2, 2), 1)
	check(str(result.error).is_empty(), "rotated stamp valid")
	target.restore_data(result.snapshot)
	check(target.monster_spawn_points[0].cells == [Vector3i(4, 0, 3), Vector3i(4, 0, 4)], "rotation and translation correct")
	check(target.monster_spawn_points[0].activation_radius == 24.0,
		"prefab transforms retain same radius in meters")
	result = prefab.stamp(target, Vector2i(9, 9), 0)
	target.restore_data(result.snapshot)
	check(target.monster_spawn_points.size() == 2 and str(target.monster_spawn_points[0].id) != str(target.monster_spawn_points[1].id), "two stamps distinct IDs")
	var gen := WorldGenerator.new()
	var shifted := gen._shift_prefab(prefab, 1)
	check(shifted.prefab.fragment.monster_spawn_points[0].cells[0].y == 1, "height alignment shifts point")
	var config := EncounterConfig.default_config()
	var rule := {"path": "res://data/monsters/wolf.tres", "ecosystems": PackedStringArray(["desert"]), "max_health": 99}
	var ordinary := config.ordinary_definition(rule)
	check(ordinary.ecosystems == PackedStringArray(["grass"]) and ordinary.max_health == 99, "ordinary ecology strictly source table")
	for specification in [["grass", "wolf", true], ["rock", "wolf", false], ["sand", "ostrich", true],
			["rock", "gorilla", true], ["sand", "gorilla", false], ["water", "goose", true],
			["water", "wolf", false], ["water", "piranha", true]]:
		var ecology_map := fixture(Vector2i(4, 4))
		var layer := 1 if specification[0] == "water" else 0
		ecology_map.set_layer(Vector2i(1, 1), layer, {"tile_id": specification[0]})
		var ecology_point := MonsterSpawnPoints.create()
		ecology_point.cells = [Vector3i(1, layer, 1)]
		var monster := load("res://data/monsters/%s.tres" % specification[1]) as MonsterDefinition
		var nav := EncounterNavigation.new()
		nav.build(ecology_map, monster)
		check((not nav.point_candidates(ecology_point, monster).is_empty()) == specification[2], "table ecology %s %s" % [specification[0], specification[1]])
	await runtime()
	await range_and_tracking()
	await generation()
	print("SPAWN POINT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)

func runtime() -> void:
	var map := fixture()
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	map.encounter.count_min = 2
	map.encounter.count_max = 2
	map.encounter.monster_pool = [{"path": "res://data/monsters/wolf.tres", "weight": 1, "enabled": true}]
	var point := MonsterSpawnPoints.create("远处静止区")
	point.cells = [Vector3i(1, 0, 1), Vector3i(2, 0, 1)]
	point.activation_radius = 20.0
	map.monster_spawn_points.append(point)
	for y in 16:
		map.remove_layer(Vector2i(4, y), 0)
	for cell: Vector3i in point.cells:
		EncounterRegions.paint(map, Vector2i(cell.x, cell.z), 0, 1)
	EncounterRegions.paint(map, map.spawn_cell, 0, 1)
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.level_data = map
	world.add_child(builder)
	var player := Node3D.new()
	player.position = map.world_center(map.spawn_cell, 0) + Vector3.UP * 0.8
	world.add_child(player)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(map, player)
	director.control_ready = false
	director.set_physics_process(false)
	await physics_frame
	director._physics_process(60)
	check(director.actors.is_empty(), "wait for control")
	director.control_ready = true
	var inside_position := player.position
	player.position = MonsterSpawnPoints.center(map, point) + Vector3(21, 0.8, 0)
	director._physics_process(90)
	check(director.actors.is_empty() and not director.point_clocks.has(str(point.id)), "outside radius no spawn and no point clock")
	player.position = inside_position
	director._physics_process(29)
	check(director.actors.is_empty(), "before 30 no actors")
	player.position = MonsterSpawnPoints.center(map, point) + Vector3(21, 0.8, 0)
	director._physics_process(90)
	check(director.actors.is_empty() and director.point_clocks[str(point.id)] == 29, "leaving radius pauses accrued clock")
	player.position = inside_position
	director._physics_process(1)
	check(director.point_alive(str(point.id)) == 2, "returning completes30s even on disconnected static island")
	var valid := true
	for actor in director.actors:
		actor.set_physics_process(false)
		valid = valid and map.world_to_cell(actor.position) in [Vector2i(1, 1), Vector2i(2, 1)]
		valid = valid and actor.definition.monster_id == "wolf"
	check(valid, "actual snapped spawn within group and matching species")
	director._physics_process(90)
	check(director.actors.size() == 2, "alive limit prevents accumulation")
	director.actors[0].take_damage(10000, "player")
	await process_frame
	director._physics_process(29)
	check(director.actors.size() == 1, "death waits for next cycle")
	director._physics_process(1)
	check(director.actors.size() == 2, "next30 replenishes")
	for actor in director.actors.duplicate():
		actor.take_damage(10000, "environment")
	await process_frame
	for cell: Vector3i in point.cells:
		EncounterRegions.paint(map, Vector2i(cell.x, cell.z), 0, 2)
	director._physics_process(30)
	check(director.actors.is_empty(), "forbidden stops point spawn")
	map.monster_spawn_points.clear()
	director._physics_process(120)
	check(director.actors.is_empty(), "no points no legacy ring waves")
	world.queue_free()
	await process_frame

func range_and_tracking() -> void:
	var map := fixture(Vector2i(32, 32))
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	map.encounter.count_max = 1
	map.encounter.monster_pool = [{"path": "res://data/monsters/wolf.tres", "enabled": true}]
	var point := MonsterSpawnPoints.create("警戒范围")
	point.activation_radius = 10.0
	point.cells = [Vector3i(16, 0, 16)]
	map.monster_spawn_points.append(point)
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.level_data = map
	world.add_child(builder)
	var player := Node3D.new()
	player.position = map.world_center(Vector2i(18, 16), 0) + Vector3.UP * 0.8
	world.add_child(player)
	var hp := CombatHealth.new()
	hp.name = "CombatHealth"
	player.add_child(hp)
	hp.setup(1000)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(map, player)
	director.control_ready = true
	director.set_physics_process(false)
	await physics_frame
	director._physics_process(30)
	check(director.actors.size() == 1, "in range actual actor spawns")
	var actor: MonsterActor = director.actors[0]
	var home := actor.home_position
	check(actor.spawn_radius == director.point_radius(point) and actor.spawn_center == MonsterSpawnPoints.center(map, point),
		"actor and director share exact point-centered radius")
	for i in 45:
		await physics_frame
	check(actor.position.distance_to(home) > 1, "monster chases player within range")
	player.position = actor.spawn_center + Vector3(12, 0.8, 0)
	actor.global_position = actor.spawn_center + Vector3(11, 0, 0)
	actor.take_damage(1, "player")
	actor.windup_left = 0.01
	actor._physics_process(0.02)
	check(actor.returning_home and actor.windup_left < 0 and hp.current == 1000,
		"outside point circle cancels windup and provocation cannot expand chase")
	for i in 180:
		await physics_frame
	check(actor.position.distance_to(home) < 0.4, "out of range actor actually returns to original spawn grid")
	actor.set_physics_process(false)
	player.position = home + Vector3(4, 0.8, 0)
	actor.repath()
	check(not actor.returning_home and actor.path.size() > 1, "reentry resumes pursuit")
	var projectile := MonsterProjectile.new()
	projectile.target = player
	projectile.spawn_center = actor.spawn_center
	projectile.spawn_radius = actor.spawn_radius
	world.add_child(projectile)
	player.position = actor.spawn_center + Vector3(12, 0.8, 0)
	projectile._physics_process(0.01)
	check(projectile.is_queued_for_deletion(), "projectile cannot hurt outside same range")
	player.position = map.world_center(map.spawn_cell, 0) + Vector3.UP * 0.8
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var profile := load("res://data/art_profile.tres") as ArtProfile
	profile.configure(camera, player.position - Vector3.UP * 0.8)
	point.activation_radius = 0.0
	point.cells = [Vector3i(16, 0, 27)]
	director._update_point_ranges()
	var center := MonsterSpawnPoints.center(map, point)
	var visible := not camera.is_position_behind(center) and Rect2(Vector2.ZERO, root.size).has_point(camera.unproject_position(center))
	check(not visible and director.point_active(point), "automatic radius activates an actually offscreen point")
	director._physics_process(30)
	check(director.actors.size() == 2, "unseen point spawns for discovery")
	print("AUTOMATIC POINT RADIUS ", director.automatic_point_radius)
	world.queue_free()
	await process_frame

func generation() -> void:
	var sample := load("res://data/worldgen_spawn_points_recipe.tres") as WorldGenConfig
	var sample_generator := WorldGenerator.new()
	check(sample_generator.prepare(sample).is_empty(), "saved sample recipe imports actual special-map resource")
	var sample_result := sample_generator.generate()
	check(str(sample_result.error).is_empty() and sample_result.data.monster_spawn_points.size() == 2,
		"saved sample recipe generates both prefab spawn points")
	var source := fixture(Vector2i(4, 4))
	var point := MonsterSpawnPoints.create("预制点")
	point.cells = [Vector3i(1, 0, 1), Vector3i(2, 0, 1)]
	source.monster_spawn_points.append(point)
	var source_path := "user://spawn-point-world-source.tres"
	ResourceSaver.save(source, source_path)
	# prepare accepts project resources; direct private fixture avoids altering source maps.
	var config := WorldGenConfig.new()
	config.width = 32
	config.height = 32
	config.static_count = 0
	config.resource_density = 0
	config.environment_density = 0
	config.prefab_budget = 0
	var generator := WorldGenerator.new()
	check(generator.prepare(config).is_empty(), "generation prepare")
	var result := generator.generate()
	var generated: LevelData = result.data
	var prefab: LevelPrefab = LevelPrefab.capture(source, source.map_bounds()).prefab
	generator._data = generated
	var stamp := generator._stamp_prefab(prefab, Vector2i(2, 2), 0, {}, 1)
	check(str(stamp.error).is_empty() and stamp.snapshot.monster_spawn_points[0].cells[0].y == 1, "real world stamp includes point and aligned layer")
	var edit := MonsterSpawnPoints.create("配方手工点")
	edit.cells = [Vector3i(16, 1, 16), Vector3i(17, 1, 16)]
	config.spawn_point_edits = [edit]
	generator = WorldGenerator.new()
	generator.prepare(config)
	result = generator.generate()
	check(str(result.error).is_empty() and result.data.monster_spawn_points == [edit], "recipe hand points survive generation")
	var again := WorldGenerator.new()
	again.prepare(config)
	var repeated := again.generate()
	check(repeated.data.clone_data() == result.data.clone_data(), "point generation deterministic")
	ResourceSaver.save(config, "/tmp/spawn-point-recipe.tres")
	var reloaded := ResourceLoader.load("/tmp/spawn-point-recipe.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as WorldGenConfig
	check(reloaded.spawn_point_edits == config.spawn_point_edits, "recipe roundtrip")
	config.spawn_point_edits.clear()
	config.prefab_budget = 2
	generator = prepared_with_source(config, prefab)
	result = generator.generate()
	check(str(result.error).is_empty() and result.data.monster_spawn_points.size() == 2,
		"full algorithm carries two special-map points")
	if str(result.error).is_empty():
		check(result.data.monster_spawn_points[0].id != result.data.monster_spawn_points[1].id
			and result.data.monster_spawn_points[0].cells[0].y == 1, "generated copies stable independent aligned IDs")
		again = prepared_with_source(config, prefab)
		repeated = again.generate()
		check(repeated.data.clone_data() == result.data.clone_data(), "prefab point worlds deterministic")
		var changed: Dictionary = result.data.monster_spawn_points[0].duplicate(true)
		changed.name = "策划重命名"
		config.spawn_point_edits = [changed, {"id": result.data.monster_spawn_points[1].id, "deleted": true}]
		again = prepared_with_source(config, prefab)
		repeated = again.generate()
		check(str(repeated.error).is_empty() and repeated.data.monster_spawn_points == [changed],
			"recipe replacements and deletions survive regeneration")

func prepared_with_source(config: WorldGenConfig, prefab: LevelPrefab) -> WorldGenerator:
	var generator := WorldGenerator.new()
	generator.prepare(config)
	generator._sources.append({"prefab": prefab,
		"rule": {"path": "test-source", "minimum": 2, "maximum": 2, "weight": 1, "zone": "any", "rotate": true},
		"entries": generator._source_entries(prefab.fragment, {}, {}),
		"padding": {}, "height_offset": 1, "collectibles": [],
		"name": "测试特殊地图", "rotation_blocker": "",
		"digest": var_to_str(prefab.fragment.clone_data()).sha256_text()})
	return generator
