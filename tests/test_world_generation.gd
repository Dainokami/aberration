extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print("WORLDGEN CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func generate(config: WorldGenConfig) -> Dictionary:
	var generator := WorldGenerator.new()
	var error := generator.prepare(config)
	if not error.is_empty():
		return {"error": error}
	return generator.generate()

func run() -> void:
	var config := WorldGenConfig.new()
	var started := Time.get_ticks_msec()
	var first := generate(config)
	check(str(first.error).is_empty(), "default world generates")
	if not str(first.error).is_empty():
		print(first)
		quit(1)
		return
	var data: LevelData = first.data
	check(data.validate().is_empty(), "real LevelData and object validation")
	check(data.map_size == Vector2i(64, 64) and data.spawn_layer == 1, "finite bounds and spawn")
	check(int(data.generation.algorithm_version) == 6, "complete prefab candidate search records new algorithm version")
	var second := generate(config)
	check(second.get("data") != null and data.clone_data() == second.data.clone_data(),
		"same seed reproduces all terrain, objects, IDs and metadata")
	config.seed_value += 1
	var different := generate(config)
	check(different.get("data") != null and data.columns != different.data.columns,
		"different seeds change terrain")
	var zone_errors := 0
	var sea_cells := 0
	var fixed_view_count := 0
	var fixed_view_rotation_errors := 0
	for record in data.objects:
		var definition: Resource = ObjectRules.definition(record)
		if not definition.supports_quarter_turns():
			fixed_view_count += 1
			if not is_zero_approx(float(record.get("yaw", 0.0))):
				fixed_view_rotation_errors += 1
		if definition.mechanism in WorldGenerator.COLLECTIBLES:
			for cell in ObjectRules.covered_cells(data, record):
				if data.generation.zones[data.index(cell)] != 1:
					zone_errors += 1
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			if data.is_water_layer(cell, 1):
				sea_cells += 1
				if not data.is_solid_layer(cell, 0):
					zone_errors += 1
	check(zone_errors == 0 and sea_cells > 0, "collectibles only static; oceans have real seabed")
	check(fixed_view_count > 0 and fixed_view_rotation_errors == 0,
		"scattered fixed-camera objects keep their authored yaw")
	var path := "/tmp/aberration-worldgen-roundtrip.tres"
	check(ResourceSaver.save(data, path) == OK, "generated map saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded != null and data.clone_data() == loaded.clone_data(), "save reload preserves metadata and map")
	var fork := data.fork_for_edit()
	fork.generation.recipe.width = 17
	check(data.generation.recipe.width == 64, "undo/fork metadata is independent")
	var empty := LevelData.new()
	empty.restore_data(data.clone_data())
	empty.setup_blank()
	check(empty.generation.is_empty(), "new blank map clears provenance")
	var source := load("res://data/prefabs/demo_camp.tres") as LevelPrefab
	var source_before := source.fragment.clone_data()
	config.prefabs = [{"path": "res://data/prefabs/demo_camp.tres",
		"minimum": 2, "maximum": 3, "weight": 1, "rotate": true, "zone": "any",
		"align_height": false}]
	var with_prefabs := generate(config)
	check(str(with_prefabs.error).is_empty(), "existing saved prefab generates")
	if not str(with_prefabs.error).is_empty():
		print(with_prefabs.error)
	else:
		var world: LevelData = with_prefabs.data
		check(world.generation.placements.size() == 3, "minimum maximum budget respected")
		var complete := true
		for placement in world.generation.placements:
			complete = complete and int(placement.turns) == 0
			for y in source.fragment.map_size.y:
				for x in source.fragment.map_size.x:
					var local := Vector2i(x, y)
					var source_cell := local + source.fragment.map_origin
					var actual: Vector2i = placement.rect.position + source.rotate_cell(local, placement.turns)
					if world.layer_count(actual) != source.fragment.layer_count(source_cell):
						complete = false
					for layer in source.fragment.layer_count(source_cell):
						if world.get_layer(actual, layer).get("tile_id", "") != source.fragment.get_layer(
								source_cell, layer).get("tile_id", ""):
							complete = false
		check(complete, "with height alignment disabled prefab columns preserve original layers and air")
		var warned := false
		for warning in with_prefabs.warnings:
			warned = warned or str(warning).contains("固定视角物件")
		check(warned, "worldgen reports why fixed-camera prefabs keep their authored direction")
		var repeat := generate(config)
		check(repeat.get("data") != null and world.clone_data() == repeat.data.clone_data(),
			"prefab random IDs remapped deterministically")
	check(source.fragment.clone_data() == source_before, "source prefab remains unchanged")
	var map_config := WorldGenConfig.new()
	map_config.prefabs = [{"path": "res://data/levels/dynamic_splat_acceptance.tres",
		"minimum": 1, "maximum": 1, "weight": 1, "zone": "any", "rotate": true}]
	var saved_map := generate(map_config)
	check(str(saved_map.error).is_empty() and saved_map.data.generation.placements.size() == 1,
		"saved LevelData map is accepted directly as a special tile")
	config.prefab_budget = 1
	check(not str(generate(config).error).is_empty(), "impossible required budget rejected")
	config = WorldGenConfig.new()
	config.width = 601
	check(not str(generate(config).error).is_empty(), "bounds above 600 rejected")
	config = WorldGenConfig.new()
	config.resource_density = 0
	config.environment_density = 0
	config.spawn_radius = 2
	for size in [Vector2i(16, 16), Vector2i(48, 24), Vector2i(128, 96)]:
		config.width = size.x
		config.height = size.y
		for seed_value in [0, 42, 2147483647]:
			config.seed_value = seed_value
			var output := generate(config)
			check(str(output.error).is_empty() and output.data.map_size == size,
				"size %s seed %d" % [size, seed_value])
	var generator := WorldGenerator.new()
	check(generator.prepare(config).is_empty(), "cancel case prepares")
	generator.cancel()
	check(generator.generate().error == "已取消", "cancel returns no partial map")
	print("WORLDGEN TIME ms ", Time.get_ticks_msec() - started)
	print("WORLDGEN FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
