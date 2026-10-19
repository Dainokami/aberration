extends SceneTree

var failures: Array[String] = []
var checks := 0
const SEEDS := [0, 1, 2, 3, 42, 4242, 20261018, 2147483647]

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("LAYOUT CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func config_for_test() -> WorldGenConfig:
	var config := WorldGenConfig.new()
	config.resource_density = 0
	config.environment_density = 0
	# Neither regional noise nor absent random biomes can defeat a required slot.
	config.region_count = 64
	config.boundary_noise = 1.0
	config.grass_weight = 1
	config.rock_weight = 0
	config.sand_weight = 0
	config.water_weight = 0
	config.static_count = 0
	return config

func source(size: Vector2i, terrain: String, count := 1) -> Dictionary:
	var prefab := LevelPrefab.new()
	prefab.fragment = LevelData.new()
	prefab.fragment.setup_blank(size)
	for i in prefab.fragment.columns.size():
		prefab.fragment.columns[i] = {"layers": [{"tile_id": "grass", "rotation": 0}]}
	var generator := WorldGenerator.new()
	return {"prefab": prefab, "rule": {"path": "test_" + terrain, "terrain": terrain,
		"minimum": count, "maximum": count, "rotate": false, "zone": "static"},
		"entries": generator._source_entries(prefab.fragment, {}, {}),
		"padding": {}, "height_offset": 1, "collectibles": [], "name": terrain,
		"rotation_blocker": "", "digest": "fixture"}

func verify_world(generator: WorldGenerator, output: Dictionary, label: String) -> void:
	check(str(output.error).is_empty(), label + " generates")
	if not str(output.error).is_empty():
		print(output.error)
		return
	var data: LevelData = output.data
	var required := 0
	for entry in generator._sources:
		required += int(entry.rule.get("minimum", 1))
	check(data.generation.placements.size() == required, label + " required counts")
	check(data.map_size.x >= generator._config.width and data.map_size.y >= generator._config.height
		and data.map_size.x <= 600 and data.map_size.y <= 600, label + " bounded automatic size")
	var valid := true
	for i in data.generation.placements.size():
		var placement: Dictionary = data.generation.placements[i]
		var rect: Rect2i = placement.rect
		valid = valid and generator._terrain_matches(rect, placement.terrain) \
			and data.map_bounds().encloses(rect.grow(2)) \
			and not Rect2(rect).grow(generator._config.spawn_radius + 1).has_point(data.spawn_cell)
		for j in range(i + 1, data.generation.placements.size()):
			valid = valid and not rect.grow(maxi(2, generator._config.prefab_gap)).intersects(
				data.generation.placements[j].rect)
	check(valid, label + " strict biome, border, spacing and spawn clearance")
	var extended := true
	for placement in data.generation.placements:
		extended = extended and generator._terrain_matches(placement.rect.grow(1), placement.terrain)
	check(extended, label + " biome grows beyond the required one-cell border")
	check(data.validate().is_empty() and generator._check_reachability().is_empty(),
		label + " data and actual entrance reachability")
	var spawn_index := data.index(data.spawn_cell)
	check(generator._zones[spawn_index] == 0 and data.tile_id(data.spawn_cell) == "grass",
		label + " spawn stays on exploration land")

func run() -> void:
	var fixtures: Array[Dictionary] = [source(Vector2i(28, 28), "sand"),
		source(Vector2i(77, 77), "grass"), source(Vector2i(44, 57), "rock")]
	var config := config_for_test()
	var before := config.snapshot()
	var generator: WorldGenerator
	var first: LevelData
	for seed_value in SEEDS:
		config.seed_value = seed_value
		generator = WorldGenerator.new()
		check(generator.prepare(config).is_empty(), "prepare seed %d" % seed_value)
		generator._sources.assign(fixtures)
		var output := generator.generate()
		verify_world(generator, output, "three large maps seed %d" % seed_value)
		if not output.has("data"):
			continue
		var static_ok := true
		for placement in output.data.generation.placements:
			static_ok = static_ok and generator._placement_sum("zone:static", placement.rect) == 0
		check(static_ok, "static region reserved even with zero static cores")
		if seed_value == 0:
			first = output.data
			var repeated := generator.generate()
			check(repeated.has("data") and repeated.data.clone_data() == first.clone_data(),
				"reusing generator after expansion reproduces the entire world")
			check(ResourceSaver.save(first, "/tmp/worldgen-layout-map.tres") == OK,
				"expanded map saves")
			var loaded := ResourceLoader.load("/tmp/worldgen-layout-map.tres", "",
				ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			check(loaded.clone_data() == first.clone_data(), "expanded map reload exact")
			var restored := WorldGenConfig.new()
			for field in WorldGenConfig.FIELDS:
				restored.set(field, loaded.generation.recipe[field])
			var replay := WorldGenerator.new()
			replay.prepare(restored)
			replay._sources.assign(fixtures)
			var replayed := replay.generate()
			check(replayed.has("data") and replayed.data.clone_data() == first.clone_data(),
				"saved recipe uses original requested size and reproduces auto expansion")
	config.seed_value = before.seed_value
	check(config.snapshot() == before, "generation never edits caller recipe")
	check(fixtures[1].prefab.fragment.map_size == Vector2i(77, 77)
		and fixtures[1].prefab.fragment.top_layer(Vector2i.ZERO) == 0, "source dimensions and height unchanged")

	# Geometry-only coverage includes the hard upper bound without allocating
	# hundreds of thousands of LevelData columns for each packing attempt.
	var planner := WorldLayoutPlanner.new()
	var never_stop := func(): return false
	var large := source(Vector2i(1, 1), "grass")
	large.prefab.fragment.map_size = Vector2i(500, 500)
	config.width = 600
	config.height = 600
	var plan := planner.plan(config, [large], never_stop)
	check(str(plan.error).is_empty() and plan.size == Vector2i(600, 600)
		and plan.spawn != Vector2i(300, 300), "large source moves spawn out of the way instead of failing at center")
	large.prefab.fragment.map_size = Vector2i(597, 597)
	var started := Time.get_ticks_msec()
	plan = planner.plan(config, [large], never_stop)
	check(str(plan.error).contains("600×600") and str(plan.error).contains("597×597")
		and not plan.has("placements") and Time.get_ticks_msec() - started < 2000,
		"impossible upper bound fails promptly with source dimensions")
	check(planner.plan(config, fixtures, func(): return true).error == "已取消",
		"packing is cancellable without partial output")

	config = config_for_test()
	config.width = 96
	config.height = 24
	config.spawn_radius = 2
	var narrow := source(Vector2i(12, 48), "rock")
	narrow.rule.rotate = true
	plan = planner.plan(config, [narrow], never_stop)
	check(str(plan.error).is_empty() and plan.size == Vector2i(96, 24)
		and plan.placements[0].turns % 2 == 1, "narrow world uses a fitting allowed rotation without expansion")
	narrow.rotation_blocker = "fixed-camera asset"
	plan = planner.plan(config, [narrow], never_stop)
	check(str(plan.error).is_empty() and plan.size.y > 24 and plan.placements[0].turns == 0,
		"fixed view remains unrotated and expands instead")

	config = config_for_test()
	config.width = 16
	config.height = 16
	config.spawn_radius = 2
	config.prefab_budget = 32
	config.prefab_gap = 1
	var many := source(Vector2i(5, 7), "sand", 32)
	generator = WorldGenerator.new()
	generator.prepare(config)
	generator._sources.assign([many])
	verify_world(generator, generator.generate(), "32 mandatory copies with minimum gap")

	var collectible := source(Vector2i(4, 4), "grass")
	collectible.collectibles = [Vector2i.ONE]
	collectible.rule.zone = "any"
	generator = WorldGenerator.new()
	generator.prepare(config_for_test())
	generator._sources.assign([collectible])
	var output := generator.generate()
	verify_world(generator, output, "collectible support in otherwise nonstatic world")
	if output.has("data"):
		var placement: Dictionary = output.data.generation.placements[0]
		check(generator._zones[output.data.index(placement.rect.position + Vector2i.ONE)] == 1,
			"collectible footprint receives static label")
	collectible.rule.zone = "explore"
	generator._sources.assign([collectible])
	output = generator.generate()
	check(str(output.error).contains("规则冲突") and not output.has("data"),
		"contradictory explore and collectible requirements rejected explicitly")

	# Opt-in integration with the user's private maps; not a repository dependency.
	if "--user-prefabs" in OS.get_cmdline_user_args():
		await user_prefabs()
	print("LAYOUT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)

func user_prefabs() -> void:
	var config := config_for_test()
	var originals := {}
	for spec in [["Desert", "sand"], ["Meadow", "grass"], ["Rocky", "rock"]]:
		var path := "res://data/levels/Prefab_Level%s.tres" % spec[0]
		check(ResourceLoader.exists(path), "private source exists " + path)
		if not ResourceLoader.exists(path):
			return
		originals[path] = (load(path) as LevelData).clone_data()
		config.prefabs.append({"path": path, "minimum": 1, "maximum": 1,
			"terrain": spec[1], "zone": "any", "rotate": false})
	for seed_value in SEEDS:
		config.seed_value = seed_value
		var generator := WorldGenerator.new()
		var error := generator.prepare(config)
		check(error.is_empty(), "private maps prepare seed %d" % seed_value)
		if not error.is_empty():
			print(error)
			continue
		var started := Time.get_ticks_msec()
		var output := generator.generate()
		verify_world(generator, output, "private maps seed %d" % seed_value)
		if output.has("data"):
			print("PRIVATE WORLD seed ", seed_value, " size ", output.data.map_size,
				" ms ", Time.get_ticks_msec() - started)
	for path: String in originals:
		check((load(path) as LevelData).clone_data() == originals[path], "private source stays unchanged " + path)
