extends SceneTree

const OUTPUT_PATH := "res://data/levels/dynamic_splat_acceptance.tres"

func _init() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(16, 16))
	var cells := {}
	var official := ["grass", "rock", "sand", "water"]
	var custom := [
		"ground_forest", "ground_stone", "decal_marsh", "decal_corruption"]
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			var tile_id := "water"
			var height := 0
			var exists := true
			if y < 8:
				var quadrant := (1 if x % 8 >= 4 else 0) + (2 if y >= 4 else 0)
				tile_id = official[quadrant] if x < 8 else custom[quadrant]
			elif x >= 2 and x <= 13 and y >= 9 and y <= 14:
				height = 1
				var local_x := x - 2
				var band := mini(floori(float(local_x) / 3.0), 3)
				tile_id = official[band] if y <= 11 else custom[band]
			elif y >= 9 and (x < 2 or x > 13):
				exists = false
			cells[cell] = {
				"exists": exists,
				"terrain": TileRegistry.id_to_legacy_terrain(tile_id),
				"height": height,
				"tile_id": tile_id,
				"rotation": posmod(x + y, 4) if tile_id in custom else 0,
			}
	data.set_cells(cells)
	data.spawn_cell = Vector2i(3, 10)
	var error := ResourceSaver.save(data, OUTPUT_PATH)
	print("DYNAMIC SPLAT ACCEPTANCE SAVE: ", error)
	quit(error)
