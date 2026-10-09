extends SceneTree

func _init() -> void:
	var blank := LevelData.new()
	blank.setup_blank()
	var result := ResourceSaver.save(blank, "res://data/levels/blank_map.tres")
	if result != OK:
		push_error("Failed to save blank fixture")
		quit(1)
		return
	var level := LevelData.new()
	level.setup_blank()
	# Three plateaus with two north-facing 0→2m and 2→4m stairs.
	for y in range(8, 16):
		for x in range(2, 14):
			level.set_cell(Vector2i(x, y), {"exists": true, "terrain": 0, "height": 0})
	for y in range(4, 8):
		for x in range(2, 14):
			level.set_cell(Vector2i(x, y), {"exists": true, "terrain": 1, "height": 1})
	for y in range(0, 4):
		for x in range(2, 14):
			level.set_cell(Vector2i(x, y), {"exists": true, "terrain": 0, "height": 2})
	level.stairs = [
		{"cell": Vector2i(7, 8), "direction": 0},
		{"cell": Vector2i(7, 4), "direction": 0},
	]
	level.spawn_cell = Vector2i(7, 13)
	result = ResourceSaver.save(level, "res://data/levels/acceptance_map.tres")
	if result != OK:
		push_error("Failed to save acceptance fixture")
		quit(1)
		return
	print("Generated level fixtures")
	quit()
