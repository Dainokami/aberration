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
	print("DATA TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
