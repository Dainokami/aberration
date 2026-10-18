extends SceneTree

func _init() -> void:
	var map := create_map()
	var error := ResourceSaver.save(map, "res://data/levels/encounter_demo.tres")
	print("ENCOUNTER DEMO SAVED ", error, " VALIDATION ", map.validate())
	quit(0 if error == OK and map.validate().is_empty() else 1)

static func create_map() -> LevelData:
	var map := LevelData.new()
	map.setup_blank(Vector2i(32, 32))
	for y in 32:
		for x in 32:
			var id := "painted_grass"
			if x < 8:
				id = "ground_stone"
			elif x > 25:
				id = "sand"
			map.set_layer(Vector2i(x, y), 0, {"tile_id":id})
			if y < 3:
				map.set_layer(Vector2i(x, y), 1, {"tile_id":"water"})
	map.spawn_cell = Vector2i(16, 16)
	map.spawn_layer = 0
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	map.encounter.elite_one_ecosystems = PackedStringArray(["grass","rock"])
	map.encounter.elite_two_ecosystems = PackedStringArray(["grass","rock"])
	for y in range(12, 16):
		for x in range(12, 16):
			EncounterRegions.paint(map, Vector2i(x,y), 0, 1)
	for y in range(20, 23):
		for x in range(14, 18):
			EncounterRegions.paint(map, Vector2i(x,y), 0, 2)
	for cell in [Vector2i(19,16),Vector2i(19,17),Vector2i(19,18)]:
		map.objects.append(ObjectRules.anchor_record(map, {"id":"encounter_rock_%s"%cell,
			"definition":"res://assets/generated/painted_rock/definition.tres",
			"position":map.world_center(cell,0),"yaw":0.0,"scale":1.0}))
	for y in range(7, 11):
		for x in range(12, 18):
			map.set_layer(Vector2i(x,y), 1, {"tile_id":"ground_stone"})
	map.stairs.append({"cell":Vector2i(15,11),"layer":0,"direction":0})
	return map
