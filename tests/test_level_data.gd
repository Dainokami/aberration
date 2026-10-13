extends SceneTree

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	print("DATA CHECK ", message, " ", value)
	if not value:
		failures.append(message)

func _init() -> void:
	var data := LevelData.new()
	data.setup_blank()
	check(data.cells.size() == 256, "blank_size")
	check(data.world_to_cell(data.world_center(Vector2i(3, 5))) == Vector2i(3, 5), "coordinate_roundtrip")
	data.set_cell(Vector2i(5, 6), {"exists": true, "terrain": 1, "height": 0})
	data.set_cell(Vector2i(5, 5), {"exists": true, "terrain": 0, "height": 1})
	check(data.can_place_stair(Vector2i(5, 6), 0).is_empty(), "valid_stair")
	data.stairs.append({"cell": Vector2i(5, 6), "direction": 0})
	check(data.stair_at(Vector2i(5, 6)) == 0 and data.stair_at(Vector2i(5, 5)) == 0, "stair_occupancy")
	check(not data.can_place_stair(Vector2i(5, 6), 0).is_empty(), "reject_overlap")
	data.spawn_cell = Vector2i(5, 6)
	var path := "res://data/levels/test_roundtrip.tres"
	check(ResourceSaver.save(data, path) == OK, "save")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded != null and loaded.spawn_cell == data.spawn_cell, "load")
	check(loaded.stairs == data.stairs and loaded.cells == data.cells, "roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var expanded := LevelData.new()
	expanded.setup_blank(Vector2i(4, 4))
	expanded.set_cell(Vector2i(0, 1), {
		"exists": true, "terrain": 0, "height": 0,
		"tile_id": "grass", "rotation": 0})
	expanded.set_cell(Vector2i(1, 1), {
		"exists": true, "terrain": 1, "height": 1,
		"tile_id": "rock", "rotation": 0})
	expanded.stairs.append({"cell": Vector2i(0, 1), "direction": 1})
	expanded.spawn_cell = Vector2i(0, 1)
	var object_position := expanded.world_center(Vector2i(1, 1))
	expanded.objects.append({"position": object_position})
	var grass_world := expanded.world_center(Vector2i(0, 1))
	var rock_world := expanded.world_center(Vector2i(1, 1))
	check(expanded.expand_to_include(
		Rect2i(Vector2i(-2, -1), Vector2i(3, 3))).is_empty(),
		"expand negative bounds")
	check(expanded.expand_to_include(
		Rect2i(Vector2i(7, 6), Vector2i(3, 3))).is_empty(),
		"expand positive bounds")
	check(expanded.map_origin.x < 0 and expanded.map_origin.y < 0
		and expanded.in_bounds(Vector2i(9, 8)), "expanded bounds include brush")
	check(expanded.tile_id(Vector2i(0, 1)) == "grass"
		and expanded.tile_id(Vector2i(1, 1)) == "rock",
		"expansion preserves logical cell coordinates")
	check(expanded.world_center(Vector2i(0, 1)).is_equal_approx(grass_world)
		and expanded.world_center(Vector2i(1, 1)).is_equal_approx(rock_world)
		and expanded.world_to_cell(grass_world) == Vector2i(0, 1),
		"expansion preserves world coordinates")
	check(expanded.stairs == [{"cell": Vector2i(0, 1), "direction": 1}]
		and expanded.spawn_cell == Vector2i(0, 1)
		and expanded.objects[0]["position"] == object_position,
		"expansion preserves stairs spawn and objects")
	var expanded_snapshot := expanded.clone_data()
	var expanded_restored := LevelData.new()
	expanded_restored.restore_data(expanded_snapshot)
	check(expanded_restored.map_origin == expanded.map_origin
		and expanded_restored.grid_world_origin == expanded.grid_world_origin
		and expanded_restored.world_center(Vector2i(0, 1)).is_equal_approx(grass_world),
		"expanded bounds survive snapshot roundtrip")
	print("DATA TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
