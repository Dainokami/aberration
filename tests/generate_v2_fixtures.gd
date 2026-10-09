extends SceneTree

func _init() -> void:
	var definitions := [
		["tree", "分层树木", Vector2(4, 5), Vector3(0.7, 2, 0.7), 2],
		["rock", "岩石", Vector2(2.5, 2.5), Vector3(1.3, 1, 1.3), 1],
		["tent", "帐篷", Vector2(4, 4), Vector3(2, 2, 2), 1],
		["fence", "围栏", Vector2(3, 2), Vector3(2.5, 1, 0.3), 1],
		["grass", "草丛", Vector2(1.5, 1.5), Vector3(0.4, 0.4, 0.4), 0],
	]
	for spec in definitions:
		var d := PlaceableDefinition.new()
		d.asset_id = "demo_" + spec[0]
		d.display_name = spec[1]
		d.category = spec[1]
		d.source_image = "res://assets/placeholders/v2/" + spec[0] + ".png"
		d.image_size = spec[2]
		d.pivot = Vector2(0.5, 0.875)
		d.collision_size = spec[3]
		d.collision = spec[4]
		d.profile = load("res://data/art_profile.tres")
		if spec[0] == "tree":
			d.source_image = "res://assets/placeholders/v2/trunk.png"
			d.foreground_image = "res://assets/placeholders/v2/crown.png"
			d.fade_foreground = true
		var directory := "res://assets/generated/" + d.asset_id
		if not DirAccess.dir_exists_absolute(directory):
			assert(AssetFactory.generate(d, directory).is_empty())
	var map := LevelData.new()
	map.setup_blank()
	for y in range(1, 15):
		for x in range(1, 15):
			map.set_cell(Vector2i(x, y), {"exists": true, "terrain": 0, "height": 0})
	for y in range(2, 5):
		for x in range(2, 7):
			map.set_cell(Vector2i(x, y), {"exists": true, "terrain": 1, "height": 1})
	map.stairs.append({"cell": Vector2i(4, 5), "direction": 0})
	map.spawn_cell = Vector2i(8, 13)
	var placements := [
		["tree", Vector2i(2, 6)], ["tree", Vector2i(6, 6)],
		["tent", Vector2i(3, 3)], ["rock", Vector2i(6, 3)],
		["fence", Vector2i(3, 7)], ["grass", Vector2i(5, 6)],
	]
	for spec in placements:
		var record := {"id": ObjectRules.new_id(),
			"definition": "res://assets/generated/demo_" + spec[0] + "/definition.tres",
			"position": map.world_center(spec[1]), "yaw": 0.0, "scale": 1.0}
		var error := ObjectRules.validate_record(map, record)
		assert(error.is_empty(), error)
		map.objects.append(record)
	var captured := LevelPrefab.capture(map, Rect2i(2, 2, 5, 6))
	assert(captured["error"].is_empty(), captured["error"])
	var prefab: LevelPrefab = captured["prefab"]
	prefab.display_name = "高地林间营地"
	DirAccess.make_dir_recursive_absolute("res://data/prefabs")
	if not FileAccess.file_exists("res://data/prefabs/demo_camp.tres"):
		assert(ResourceSaver.save(prefab, "res://data/prefabs/demo_camp.tres") == OK)
	var stamped := prefab.stamp(map, Vector2i(9, 2), 0)
	assert(stamped["error"].is_empty(), stamped["error"])
	map.restore_data(stamped["snapshot"])
	assert(map.validate().is_empty(), "\n".join(map.validate()))
	if not FileAccess.file_exists("res://data/levels/objects_acceptance.tres"):
		assert(ResourceSaver.save(map, "res://data/levels/objects_acceptance.tres") == OK)
	print("V2 fixtures ready: five assets, two camps, prefab")
	quit()
