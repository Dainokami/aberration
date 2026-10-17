extends SceneTree

const OUTPUT := "res://data/levels/art_acceptance.tres"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(OUTPUT):
		print("Art acceptance map already exists; kept unchanged.")
		quit()
		return
	var data := make_level()
	var errors := data.validate()
	if not errors.is_empty():
		print("ART MAP ERRORS: ", errors)
		quit(1)
		return
	var result := ResourceSaver.save(data, OUTPUT)
	print("ART MAP SAVED: ", OUTPUT, " ", error_string(result),
		" objects=", data.objects.size(), " details=", data.details.size())
	quit(0 if result == OK else 1)

static func make_level() -> LevelData:
	var data := LevelData.new()
	data.setup_blank(Vector2i(14, 14))
	for y in range(1, 13):
		for x in range(1, 13):
			if (x in [1, 12]) and y in [1, 2, 11, 12]:
				continue
			var cell := Vector2i(x, y)
			var tile := "painted_meadow" if x > 8 else "painted_grass"
			if y in [9, 10] and x in range(5, 10):
				tile = "painted_earth"
			data.set_layer(cell, 0, {"tile_id": tile})
			if x in range(2, 7) and y in range(2, 7):
				data.set_layer(cell, 1, {"tile_id": "painted_grass"})
	data.stairs.append({"cell": Vector2i(6, 7), "direction": 0, "layer": 0})
	data.spawn_cell = Vector2i(7, 11)
	data.spawn_layer = 0
	_add(data, "chest", "painted_treasurebox", Vector2i(7, 9))
	_add(data, "breakable", "painted_decayrock", Vector2i(10, 9))
	_add(data, "rock", "painted_rock", Vector2i(4, 9))
	var top_rock := _record("stack_rock", "painted_rock", data.world_center(Vector2i(10, 9)) + Vector3.UP * 2)
	top_rock = ObjectRules.object_anchor(data, top_rock, "breakable", top_rock["position"])
	data.objects.append(top_rock)
	var wall := _record("breakable_wall", "painted_climb_surface", Vector3.ZERO)
	wall["yaw"] = 0.0
	wall = ObjectRules.object_anchor(data, wall, "breakable",
		data.world_center(Vector2i(10, 9)) + Vector3.BACK, true, 2)
	data.objects.append(wall)
	var cliff := ObjectRules.wall_anchor(data,
		_record("terrain_climb", "painted_climb_surface", Vector3.ZERO), Vector2i(4, 6), 1, 2)
	data.objects.append(cliff)
	for spec in [
		["tree_blue", "painted_bigtree", Vector2i(3, 3)],
		["tree_cypress", "painted_bigtree2", Vector2i(9, 3)],
		["tree_fruit", "painted_bigtree3", Vector2i(11, 5)],
		["pillar", "painted_pillar", Vector2i(3, 5)],
		["bush", "painted_smallbush", Vector2i(2, 9)],
		["flowers", "painted_samllflowers", Vector2i(9, 11)],
		["grass_big", "painted_biggrass", Vector2i(11, 7)],
		["grass_small", "painted_smallgrass", Vector2i(5, 5)],
	]:
		_add(data, spec[0], spec[1], spec[2])
	for type in ["flat", "upright"]:
		data.details.append_array(DetailRules.scatter(data, "res://data/details/painted_" + type + ".tres",
			data.world_center(Vector2i(7, 7)), 10, 140, 14102026 + type.length(),
			"sample_" + type, -1, 0.7, 0.4))
	return data

static func _record(id: String, definition: String, position: Vector3) -> Dictionary:
	return {"id": id, "definition": "res://assets/generated/" + definition + "/definition.tres",
		"position": position, "yaw": 0.0, "scale": 1.0}

static func _add(data: LevelData, id: String, definition: String, cell: Vector2i) -> void:
	data.objects.append(ObjectRules.anchor_record(data, _record(id, definition, data.world_center(cell))))
