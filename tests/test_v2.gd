extends SceneTree

var failures: Array[String] = []

func check(condition: bool, title: String) -> void:
	print("V2 CHECK ", title, " ", condition)
	if not condition:
		failures.append(title)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var old := load("res://data/levels/acceptance_map.tres") as LevelData
	check(old != null and old.objects.is_empty(), "v1 compatibility")
	var map := load("res://data/levels/objects_acceptance.tres") as LevelData
	check(map != null and map.validate().is_empty(), "v2 map valid")
	check(map.objects.size() == 12, "two camps have twelve objects")
	var snapshot := map.clone_data()
	var path := "user://v2_roundtrip.tres"
	check(ResourceSaver.save(map, path) == OK, "save")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.clone_data() == snapshot, "roundtrip includes objects")
	var record := map.objects[0].duplicate(true)
	record["position"] = Vector3(100, 0, 100)
	check(not ObjectRules.validate_record(map, record).is_empty(), "out of bounds rejected")
	record = map.objects[0].duplicate(true)
	record["id"] = ObjectRules.new_id()
	check(not ObjectRules.validate_record(map, record).is_empty(), "collision overlap rejected")
	var partial := LevelPrefab.capture(map, Rect2i(4, 4, 1, 1))
	check(not partial["error"].is_empty(), "cut stair rejected")
	var prefab := load("res://data/prefabs/demo_camp.tres") as LevelPrefab
	var empty := LevelData.new()
	empty.setup_blank()
	var before := empty.clone_data()
	for rotation in 4:
		var result := prefab.stamp(empty, Vector2i(3, 3), rotation)
		check(result["error"].is_empty(), "stamp rotation %d" % rotation)
		check(empty.clone_data() == before, "stamp is transaction %d" % rotation)
		if result["error"].is_empty():
			var candidate := LevelData.new()
			candidate.restore_data(result["snapshot"])
			var stair: Dictionary = candidate.stairs[0]
			check(stair["direction"] == rotation, "stair direction rotates %d" % rotation)
			check(ObjectRules.validate_all(candidate).is_empty(), "rotated objects valid %d" % rotation)
	check(not prefab.stamp(empty, Vector2i(15, 15), 0)["error"].is_empty(), "prefab bounds rejected")
	check(not prefab.stamp(map, Vector2i(2, 2), 0)["error"].is_empty(), "existing camp protected")
	check(map.clone_data() == snapshot, "failed stamp leaves map unchanged")
	loaded.objects.remove_at(0)
	loaded.restore_data(snapshot)
	check(loaded.clone_data() == snapshot, "snapshot undo restores deleted object")
	var d := load("res://assets/generated/demo_rock/definition.tres") as PlaceableDefinition
	var analyzed := ImageDefaults.analyze((load(d.source_image) as Texture2D).get_image(), 256)
	check(analyzed["error"].is_empty() and analyzed["pixels"] == Vector2i(256, 256),
		"generic image alpha analysis")
	check(analyzed["bounds"].size.x < 256 and analyzed["bounds"].size.y < 256,
		"transparent bounds measured")
	check(analyzed["pivot"].x >= 0 and analyzed["pivot"].x <= 1 and
		analyzed["pivot"].y >= 0 and analyzed["pivot"].y <= 1, "estimated pivot normalized")
	var first_id := ImageDefaults.available_id("123 奇怪祭坛.png", "user://missing_generated")
	check(first_id.is_valid_identifier(), "arbitrary filename gets legal id")
	var original_hash := FileAccess.get_sha256(d.source_image)
	check(not AssetFactory.generate(d, "res://assets/generated/demo_rock").is_empty(), "no overwrite existing asset")
	check(FileAccess.get_sha256(d.source_image) == original_hash, "source art unchanged")
	for carrier in [PlaceableDefinition.Carrier.PROJECTED_BOX, PlaceableDefinition.Carrier.PROJECTED_WEDGE]:
		var projected := d.duplicate(true) as PlaceableDefinition
		projected.carrier = carrier
		var node := AssetFactory.make_asset(projected)
		var arrays: Array = node.get_child(0).mesh.surface_get_arrays(0)
		var basis := projected.profile.camera_basis()
		var okay := true
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var vertex: Vector3 = basis.inverse() * arrays[Mesh.ARRAY_VERTEX][i]
			var uv := Vector2(vertex.x / projected.image_size.x + projected.pivot.x,
				projected.pivot.y - vertex.y / projected.image_size.y)
			okay = okay and uv.is_equal_approx(arrays[Mesh.ARRAY_TEX_UV][i])
		check(okay, "projected UV carrier %d" % carrier)
		node.free()
	await physical(map)
	print("V2 TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func physical(map: LevelData) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var terrain := TerrainBuilder.new()
	terrain.level_data = map
	terrain.show_grid = false
	world.add_child(terrain)
	await physics_frame
	await physics_frame
	var state := world.get_world_3d().direct_space_state
	for i in [0, 2, 5, 6, 8, 11]:
		var record := map.objects[i]
		var position: Vector3 = record["position"]
		var solid := ObjectRules.definition(record).collision != PlaceableDefinition.Collision.NONE
		var reach := 1.5 if solid else 0.8
		var query := PhysicsRayQueryParameters3D.create(position + Vector3(0, 0.4, -reach), position + Vector3(0, 0.4, reach))
		var hit := state.intersect_ray(query)
		check(not hit.is_empty() if solid else hit.is_empty(), "proxy collision / grass pass %d" % i)
	var character := CharacterBody3D.new()
	character.floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.32
	shape.shape = capsule
	character.add_child(shape)
	world.add_child(character)
	var tree_pos: Vector3 = map.objects[0]["position"]
	character.position = tree_pos + Vector3(-1.8, 0.82, 0)
	for frame in 90:
		character.velocity = Vector3(3, -1, 0)
		character.move_and_slide()
		await physics_frame
	check(character.position.x < tree_pos.x - 0.5, "capsule blocked by tree")
	var grass_pos: Vector3 = map.objects[5]["position"]
	character.position = grass_pos + Vector3(0, 0.82, -1.4)
	for frame in 55:
		character.velocity = Vector3(0, -1, 3)
		character.move_and_slide()
		await physics_frame
	check(character.position.z > grass_pos.z + 0.8, "capsule passes grass")
	world.queue_free()
	await process_frame
