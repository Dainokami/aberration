extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	print("SEAM CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func run() -> void:
	var generator := WorldGenerator.new()
	var fragment := LevelData.new()
	fragment.setup_blank(Vector2i(16, 12))
	fragment.map_origin = Vector2i(-5, -4)
	for y in range(3, 9):
		for x in range(4, 12):
			fragment.set_column(fragment.map_origin + Vector2i(x, y),
				{"layers": [{"tile_id": "rock"}, {"tile_id": "grass"}]})
	fragment.set_column(fragment.map_origin + Vector2i(7, 5), {"layers": []})
	fragment.set_column(fragment.map_origin + Vector2i(5, 4),
		{"layers": [{"tile_id": "rock"}, {}, {"tile_id": "grass"}]})
	fragment.set_column(fragment.map_origin + Vector2i(6, 4),
		{"layers": [{"tile_id": "rock"}, {"tile_id": "water"}]})
	var before := fragment.clone_data()
	var padding := generator._exterior_padding(fragment)
	check(padding.size() == 144 and padding.has(Vector2i(0, 0)),
		"unpainted outside margin is identified with a nonzero map origin")
	check(not padding.has(Vector2i(7, 5)), "enclosed hole is not exterior padding")
	check(not padding.has(Vector2i(5, 4)) and not padding.has(Vector2i(6, 4)),
		"layered air and independent water remain authored columns")
	check(not generator._source_entries(fragment, padding, {}).is_empty(),
		"fully padded fragment can connect at its actual terrain edge")
	check(generator._source_entries(fragment, {}, {}).is_empty(),
		"exact-copy mode still requires an original map-edge entrance")
	var prefab := LevelPrefab.new()
	prefab.fragment = fragment
	var base := LevelData.new()
	base.setup_blank(Vector2i(40, 40))
	for i in base.columns.size():
		base.columns[i] = {"layers": [{"tile_id": "sand"}, {"tile_id": "sand"}]}
	base.spawn_cell = Vector2i(30, 30)
	base.spawn_layer = 1
	generator._data = base
	var anchor := Vector2i(8, 8)
	for turns in 4:
		var result := generator._stamp_prefab(prefab, anchor, turns, padding)
		check(str(result.error).is_empty(), "rotated blended stamp validates: %d" % turns)
		if not str(result.error).is_empty():
			continue
		var world := LevelData.new()
		world.restore_data(result.snapshot)
		var intact := true
		var gaps := 0
		for local: Vector2i in padding:
			var cell := anchor + prefab.rotate_cell(local, turns)
			intact = intact and world.column_snapshot(cell) == base.column_snapshot(cell)
		for column in world.columns:
			if column.layers.is_empty():
				gaps += 1
		check(intact and gaps == 1, "all exterior cells filled, only authored hole remains: %d" % turns)
		var air_cell := anchor + prefab.rotate_cell(Vector2i(5, 4), turns)
		var water_cell := anchor + prefab.rotate_cell(Vector2i(6, 4), turns)
		check(world.get_layer(air_cell, 1).is_empty() and world.is_solid_layer(air_cell, 2)
			and world.is_water_layer(water_cell, 1), "air and water survive rotation: %d" % turns)
		var lifted := generator._stamp_prefab(prefab, anchor, turns, padding, 1)
		check(str(lifted.error).is_empty(), "whole-fragment height translation validates: %d" % turns)
		if str(lifted.error).is_empty():
			world.restore_data(lifted.snapshot)
			var ground := anchor + prefab.rotate_cell(Vector2i(4, 3), turns)
			var hole := anchor + prefab.rotate_cell(Vector2i(7, 5), turns)
			check(world.get_layer(ground, 0).tile_id == "sand"
				and world.get_layer(ground, 1).tile_id == "rock"
				and world.get_layer(ground, 2).tile_id == "grass"
				and world.get_layer(air_cell, 2).is_empty()
				and world.is_solid_layer(air_cell, 3)
				and world.is_water_layer(water_cell, 2) and world.top_layer(hole) < 0,
				"substrate, relative heights, air, water and holes survive lifting: %d" % turns)
	var exact := generator._stamp_prefab(prefab, anchor, 0, {})
	var manual := prefab.stamp(base, anchor, 0)
	check(exact.snapshot == manual.snapshot, "opt-out matches ordinary prefab exact-copy behavior")
	check(fragment.clone_data() == before, "blending never changes the source fragment")
	var clipped := generator._stamp_prefab(prefab, anchor, 0, padding, -1)
	check(not str(clipped.error).is_empty(), "downward alignment cannot clip authored solid layers")
	var high_fragment := LevelPrefab.new()
	high_fragment.fragment = LevelData.new()
	high_fragment.fragment.setup_blank(Vector2i(3, 3))
	high_fragment.fragment.set_column(Vector2i(1, 1), {"layers": [{}, {}, {"tile_id": "grass"}]})
	var lowered := generator._stamp_prefab(high_fragment, anchor, 0, {}, -1)
	var lower_world := LevelData.new()
	lower_world.restore_data(lowered.snapshot)
	check(str(lowered.error).is_empty() and lower_world.top_layer(anchor + Vector2i.ONE) == 1
		and lower_world.get_layer(anchor + Vector2i.ONE, 0).is_empty(),
		"downward alignment removes only empty slots and preserves floating air")
	var maximum := LevelPrefab.new()
	maximum.fragment = LevelData.new()
	maximum.fragment.setup_blank(Vector2i(3, 3))
	maximum.fragment.set_layer(Vector2i.ONE, LevelData.MAX_LAYERS - 1, {"tile_id": "rock"})
	check(not str(generator._stamp_prefab(maximum, anchor, 0, {}, 1).error).is_empty(),
		"height alignment rejects overflow without dropping terrain")

	var camp := load("res://data/prefabs/demo_camp.tres") as LevelPrefab
	var camp_copy := LevelPrefab.new()
	camp_copy.fragment = LevelData.new()
	camp_copy.fragment.restore_data(camp.fragment.clone_data())
	var detail_set := load("res://data/details/painted_upright.tres") as DetailSet
	camp_copy.fragment.details.append(DetailRules.make_record(camp_copy.fragment,
		"res://data/details/painted_upright.tres", str(detail_set.variants[0].id),
		camp_copy.fragment.world_center(Vector2i(2, 4), 0), "camp_detail"))
	var camp_before := camp_copy.fragment.clone_data()
	check(not str(generator._stamp_prefab(camp_copy, anchor, 1, {}, 1).error).is_empty(),
		"fixed-camera camp cannot rotate during height-aligned stamping")
	var camp_result := generator._stamp_prefab(camp_copy, anchor, 0, {}, 1)
	check(str(camp_result.error).is_empty(), "camp objects stairs and detail lift in authored direction")
	if str(camp_result.error).is_empty():
		var actual := LevelData.new()
		actual.restore_data(camp_result.snapshot)
		var intact := actual.objects.size() == camp_copy.fragment.objects.size()
		for i in actual.objects.size():
			var original: Dictionary = camp_copy.fragment.objects[i]
			var record: Dictionary = actual.objects[i]
			intact = intact and record.anchor_layer == original.anchor_layer + 1 \
				and is_equal_approx(record.position.y, original.position.y + LevelData.ELEVATION_STEP)
		intact = intact and actual.details.size() == 1 \
			and actual.details[0].anchor_layer == camp_copy.fragment.details[0].anchor_layer + 1 \
			and is_equal_approx(actual.details[0].position.y,
				camp_copy.fragment.details[0].position.y + LevelData.ELEVATION_STEP)
		intact = intact and actual.stairs[0].layer == camp_copy.fragment.stairs[0].layer + 1
		check(intact and actual.validate().is_empty(), "all content anchors translate exactly two meters")
	check(camp_copy.fragment.clone_data() == camp_before, "height alignment keeps original content data unchanged")

	var reference := load("res://data/levels/final_generated_special_world_64.tres") as LevelData
	var config := WorldGenConfig.new()
	for field in WorldGenConfig.FIELDS:
		if reference.generation.recipe.has(field):
			config.set(field, reference.generation.recipe[field])
	var error := generator.prepare(config)
	check(error.is_empty(), "three saved special terrains prepare")
	if error.is_empty():
		var generated := generator.generate()
		check(str(generated.error).is_empty(), "three-terrain world validates and entries are reachable")
		if str(generated.error).is_empty():
			var world: LevelData = generated.data
			var margin_count := 0
			var gap_count := 0
			var authored_intact := true
			var aligned := true
			for placement in world.generation.placements:
				var source := load(str(placement.source)) as LevelData
				var wrapper := LevelPrefab.new()
				wrapper.fragment = source
				var source_padding := generator._exterior_padding(source)
				for y in source.map_size.y:
					for x in source.map_size.x:
						var local := Vector2i(x, y)
						var cell: Vector2i = placement.rect.position + wrapper.rotate_cell(local, placement.turns)
						if source_padding.has(local):
							margin_count += 1
							if world.top_layer(cell) < 0:
								gap_count += 1
						else:
							var original_cell := source.map_origin + local
							var offset := int(placement.height_offset)
							var original_count := source.layer_count(original_cell)
							var expected_count := original_count + offset if original_count > 0 else 0
							authored_intact = authored_intact and world.layer_count(cell) == expected_count
							for layer in source.layer_count(original_cell):
								authored_intact = authored_intact and world.get_layer(cell, layer + offset).get("tile_id", "") \
									== source.get_layer(original_cell, layer).get("tile_id", "")
				aligned = aligned and placement.height_offset == 1 and placement.layer == 1 \
					and world.top_layer(placement.entry) == world.top_layer(placement.outside)
			check(world.generation.placements.size() == 3 and margin_count > 0 and gap_count == 0,
				"all three real examples have zero exterior empty columns")
			check(authored_intact, "real samples retain authored terrain and internal voids")
			check(aligned, "all three source grounds match the world surface instead of sinking one layer")
			var repeat := generator.generate()
			check(str(repeat.error).is_empty() and repeat.data.clone_data() == world.clone_data(),
				"blended world still reproduces all data with a fixed seed")
			print("SEAM SAMPLE filled margins ", margin_count,
				" objects ", world.objects.size(), " roads ", world.generation.roads.size(),
				" placements ", world.generation.placements)
	print("SEAM FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
