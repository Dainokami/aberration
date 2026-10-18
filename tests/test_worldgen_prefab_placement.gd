extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PREFAB PLACEMENT CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func fixture(world_size: Vector2i, source_size: Vector2i, rule: Dictionary) -> WorldGenerator:
	var generator := WorldGenerator.new()
	generator._config = WorldGenConfig.new()
	generator._config.width = world_size.x
	generator._config.height = world_size.y
	generator._config.spawn_radius = 2
	generator._config.resource_density = 0
	generator._config.environment_density = 0
	generator._data = LevelData.new()
	generator._data.setup_blank(world_size)
	generator._data.spawn_cell = world_size / 2
	generator._data.spawn_layer = 1
	for index in generator._data.columns.size():
		generator._data.columns[index] = {"layers": [{"tile_id": "sand"}, {"tile_id": "sand"}]}
	generator._biomes.resize(world_size.x * world_size.y)
	generator._biomes.fill(2)
	generator._zones.resize(world_size.x * world_size.y)
	generator._zones.fill(0)
	var prefab := LevelPrefab.new()
	prefab.display_name = "Prefab_LevelDesert"
	prefab.fragment = LevelData.new()
	prefab.fragment.setup_blank(source_size)
	for index in prefab.fragment.columns.size():
		prefab.fragment.columns[index] = {"layers": [{"tile_id": "sand"}, {"tile_id": "sand"}]}
	generator._sources.assign([{"prefab": prefab, "rule": rule, "name": prefab.display_name,
		"padding": {}, "height_offset": 0, "collectibles": [],
		"entries": [{"cell": Vector2i.ZERO, "direction": 0, "layer": 1}],
		"rotation_blocker": ""}])
	generator._rng.seed = 42
	return generator

func run() -> void:
	# Exactly one desert rectangle fits the selected biome. Random samples miss it.
	var generator := fixture(Vector2i(64, 64), Vector2i(3, 3),
		{"path": "test_desert.tres", "minimum": 1, "maximum": 1, "terrain": "sand", "rotate": false})
	generator._biomes.fill(0)
	var anchor := Vector2i(6, 8)
	for y in range(anchor.y - 1, anchor.y + 4):
		for x in range(anchor.x - 1, anchor.x + 4):
			generator._biomes[generator._data.index(Vector2i(x, y))] = 2
	var before: Dictionary = generator._sources[0].prefab.fragment.clone_data()
	check(generator._try_place(0) and generator._placements[0].rect.position == anchor,
		"mandatory desert prefab finds the only legal placement")
	check(generator._sources[0].prefab.fragment.clone_data() == before, "candidate search preserves source map")
	if not generator._placements.is_empty():
		check(generator._connect().is_empty() and generator._check_reachability().is_empty(),
			"rare valid placement retains its reachable entrance")

	# Only unrotated and 180-degree orientations fit the rectangular world.
	var all_seeds := true
	for seed_value in range(16):
		var rectangular := fixture(Vector2i(64, 24), Vector2i(48, 3),
			{"path": "test_desert.tres", "terrain": "sand", "rotate": true})
		rectangular._rng.seed = seed_value
		all_seeds = rectangular._try_place(0) and all_seeds
	check(all_seeds, "one oversized rotation cannot reject all usable orientations")

	# Collectible/static requirements still apply even when the whole-map zone is any.
	generator = fixture(Vector2i(32, 32), Vector2i(3, 3),
		{"path": "test_desert.tres", "terrain": "sand", "zone": "any", "rotate": false})
	generator._sources[0].collectibles = [Vector2i(1, 1)]
	anchor = Vector2i(5, 7)
	generator._zones[generator._data.index(anchor + Vector2i.ONE)] = 1
	check(generator._try_place(0) and generator._placements[0].rect.position == anchor,
		"finds rare static collectible support without relaxing its region constraint")

	generator = fixture(Vector2i(24, 24), Vector2i(3, 3),
		{"path": "test_desert.tres", "minimum": 1, "terrain": "sand", "zone": "static", "rotate": false})
	var snapshot := generator._data.clone_data()
	var error := generator._place_prefabs()
	check(not error.is_empty() and error.contains("静止") and generator._placements.is_empty()
		and generator._data.clone_data() == snapshot,
		"missing static region explains its actual constraint and leaves no partial map")

	generator = fixture(Vector2i(24, 24), Vector2i(3, 3),
		{"path": "test_desert.tres", "minimum": 1, "terrain": "sand", "rotate": false})
	generator._biomes.fill(0)
	error = generator._place_prefabs()
	check(error.contains("沙漠") and generator._placements.is_empty(),
		"absent desert cannot fall back to another biome")

	generator = fixture(Vector2i(24, 24), Vector2i(25, 25),
		{"path": "test_desert.tres", "minimum": 1, "terrain": "sand", "rotate": true})
	error = generator._place_prefabs()
	check(error.contains("25") and error.contains("24") and generator._placements.is_empty(),
		"oversized source reports source and destination sizes")
	generator = fixture(Vector2i(24, 24), Vector2i(3, 3),
		{"path": "test_desert.tres", "minimum": 1, "terrain": "sand", "rotate": false})
	generator._sources[0].prefab.fragment.stairs.append({"cell": Vector2i.ZERO, "direction": 1, "layer": 0})
	snapshot = generator._data.clone_data()
	error = generator._place_prefabs()
	check(error.contains("地图校验原因") and error.contains("投放校验达到上限")
		and int(generator._last_placement_report.stamp_attempts) == WorldGenerator.MAX_STAMP_ATTEMPTS
		and generator._data.clone_data() == snapshot,
		"content validation failure is preserved and bounded without partial writes")
	# Full rectangle checks stay cheap when a large world has no matching biome.
	generator = fixture(Vector2i(600, 600), Vector2i(16, 12),
		{"path": "test_desert.tres", "terrain": "sand", "rotate": false})
	generator._biomes.fill(0)
	var started := Time.get_ticks_msec()
	check(not generator._try_place(0) and int(generator._last_placement_report.stamp_attempts) == 0,
		"large absent-biome search avoids copying and validating the whole map")
	var elapsed := Time.get_ticks_msec() - started
	print("PREFAB PLACEMENT 600x600 search ms ", elapsed)
	check(elapsed < 10000, "600x600 constrained search remains bounded")
	print("PREFAB PLACEMENT FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
