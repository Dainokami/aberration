extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print("TERRAIN SELECTION CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func configuration(terrain: String) -> WorldGenConfig:
	var config := WorldGenConfig.new()
	config.seed_value = 42
	config.spawn_radius = 2
	config.region_count = 1
	config.grass_weight = 0
	config.rock_weight = 0
	config.sand_weight = 0
	config.water_weight = 0
	config.set({"grass": "grass_weight", "rock": "rock_weight",
		"sand": "sand_weight", "water": "water_weight"}[terrain], 1.0)
	config.static_count = 1
	config.static_radius = 200
	config.resource_density = 0
	config.environment_density = 0
	config.prefabs.assign([{"path": "res://data/levels/special_stone_ruins.tres",
		"minimum": 1, "maximum": 1, "weight": 1, "terrain": terrain, "rotate": true}])
	return config

func run() -> void:
	var source := load("res://data/levels/special_stone_ruins.tres") as LevelData
	var original := source.clone_data()
	for terrain in WorldGenerator.TILES:
		var config := configuration(terrain)
		var generator := WorldGenerator.new()
		var error := generator.prepare(config)
		check(error.is_empty(), "prepares manual choice " + terrain)
		if not error.is_empty():
			continue
		var output := generator.generate()
		check(str(output.error).is_empty(), "generates in chosen terrain " + terrain)
		if not str(output.error).is_empty():
			print(output.error)
			continue
		var world: LevelData = output.data
		var placement: Dictionary = world.generation.placements[0]
		var area: Rect2i = placement.rect.grow(1)
		var matched := true
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				matched = matched and generator._biomes[world.index(Vector2i(x, y))] \
					== WorldGenerator.TILES.find(terrain)
		check(matched and placement.terrain == terrain,
			"whole footprint and surrounding border match " + terrain)
		var wrapper := LevelPrefab.new()
		wrapper.fragment = source
		var padding := generator._exterior_padding(source)
		var preserved := true
		for y in source.map_size.y:
			for x in source.map_size.x:
				var local := Vector2i(x, y)
				if padding.has(local):
					continue
				var actual: Vector2i = placement.rect.position + wrapper.rotate_cell(local, placement.turns)
				var source_cell := source.map_origin + local
				for layer in source.layer_count(source_cell):
					preserved = preserved and world.get_layer(actual, layer + int(placement.height_offset)).get("tile_id", "") \
						== source.get_layer(source_cell, layer).get("tile_id", "")
		check(preserved, "authored terrain is preserved regardless of choice " + terrain)
		check(world.tile_id(placement.outside) == ("rock" if terrain == "water" else terrain),
			"entrance preserves land terrain; ocean receives walkable causeway " + terrain)
		var repeat := generator.generate()
		check(str(repeat.error).is_empty() and repeat.data.clone_data() == world.clone_data(),
			"manual choice is deterministic " + terrain)
		check(world.generation.recipe.prefabs[0].terrain == terrain,
			"generated metadata retains manual choice " + terrain)
	check(source.clone_data() == original, "input map remains unchanged")

	var mixed := WorldGenConfig.new()
	mixed.width = 96
	mixed.height = 96
	mixed.region_count = 6
	mixed.spawn_radius = 3
	mixed.static_count = 1
	mixed.static_radius = 200
	mixed.resource_density = 0
	mixed.environment_density = 0
	for spec in [["special_grass_plateau", "grass"], ["special_stone_ruins", "rock"],
			["special_desert_oasis", "sand"]]:
		mixed.prefabs.append({"path": "res://data/levels/%s.tres" % spec[0],
			"terrain": spec[1], "minimum": 1, "maximum": 1, "weight": 1, "rotate": true})
	var mixed_generator := WorldGenerator.new()
	var mixed_output := {}
	for seed_value in range(20):
		mixed.seed_value = seed_value
		if not mixed_generator.prepare(mixed).is_empty():
			break
		mixed_output = mixed_generator.generate()
		if str(mixed_output.error).is_empty():
			break
	check(mixed_output.has("data") and mixed_output.data.generation.placements.size() == 3,
		"three independent manual choices generate together in a mixed world")
	if mixed_output.has("data"):
		var matched := true
		for placement in mixed_output.data.generation.placements:
			matched = matched and mixed_generator._terrain_matches(placement.rect, placement.terrain)
		check(matched, "every source obeys its own biome in the same generated world")
		check(ResourceSaver.save(mixed, "/tmp/worldgen-terrain-showcase-recipe.tres") == OK
			and ResourceSaver.save(mixed_output.data, "/tmp/worldgen-terrain-showcase-map.tres") == OK,
			"mixed example saves recipe choices and resulting map")
		print("TERRAIN SELECTION MIXED SEED ", mixed.seed_value)

	var probe := WorldGenerator.new()
	probe._data = LevelData.new()
	probe._data.setup_blank(Vector2i(24, 24))
	probe._biomes.resize(24 * 24)
	probe._biomes.fill(0)
	var rect := Rect2i(4, 5, 8, 6)
	check(probe._terrain_matches(rect, "grass"), "matching rectangle accepted")
	probe._biomes[probe._data.index(Vector2i(4, 5))] = 2
	check(not probe._terrain_matches(rect, "grass"),
		"matching center cannot hide mismatched footprint corner or padding")
	probe._biomes.fill(0)
	probe._biomes[probe._data.index(Vector2i(3, 5))] = 1
	check(not probe._terrain_matches(rect, "grass"), "different biome at outside border rejected")
	check(probe._terrain_matches(rect, "any"), "explicit legacy unrestricted mode is compatible")
	probe._biomes.fill(0)
	probe._data.set_layer(Vector2i(4, 5), 0, {"tile_id": "sand"})
	check(probe._terrain_matches(rect, "grass"), "checks original world ecology before authored terrain overrides")
	probe._biomes[probe._data.index(Vector2i(9, 12))] = 2
	check(not probe._terrain_matches(Rect2i(rect.position, Vector2i(6, 8)), "grass"),
		"rotated rectangular footprint checks its new extent")
	check(not probe._terrain_matches(Rect2i(0, 0, 3, 3), "grass"),
		"matching border must fit inside finite world")

	var missing := configuration("grass")
	missing.prefabs[0].terrain = "sand"
	var generator := WorldGenerator.new()
	check(generator.prepare(missing).is_empty(), "absent target terrain is a placement issue")
	var failed := generator.generate()
	check(str(failed.error).contains("沙漠") and str(failed.error).contains("无法投放")
		and not failed.has("data"), "missing chosen biome reports failure without fallback or partial result")
	missing.prefabs[0].minimum = 0
	check(generator.prepare(missing).is_empty(), "optional missing terrain prepares")
	var optional := generator.generate()
	check(str(optional.error).is_empty() and optional.data.generation.placements.is_empty()
		and "\n".join(optional.warnings).contains("沙漠"),
		"optional source is skipped with terrain-specific warning")
	missing.prefabs[0].terrain = "unset"
	check("\n".join(missing.errors()).contains("选择放置地形"), "new source requires explicit choice")
	missing.prefabs[0].terrain = "invalid"
	check("\n".join(missing.errors()).contains("放置地形无效"), "unknown terrain rejected")
	missing.prefabs[0].erase("terrain")
	check(missing.errors().is_empty(), "old recipe has unrestricted compatibility")
	print("TERRAIN SELECTION FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
