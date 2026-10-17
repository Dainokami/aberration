extends SceneTree

const MANIFEST := "res://assets/derived_art/scene_pack_20261016/manifest.json"
const Picker := preload("res://addons/terrain_editor/block_picker.gd")
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("OCEAN1016 CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func run() -> void:
	await check_water()
	await check_assets()
	check_movement()
	var report := {"failures": failures, "assets": results}
	var file := FileAccess.open("res://docs/ocean_scene_assets_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("OCEAN1016 FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_water() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(5, 5))
	var cell := Vector2i(2, 2)
	check(data.set_layer(cell, 0, {"tile_id": "water"}).is_empty()
		and data.is_water_layer(cell, 0) and not data.has_terrain_volume(cell, 0),
		"water is a standalone block on an empty grid")
	data.set_layer(cell, 1, {"tile_id": "water"})
	check(data.layer_count(cell) == 2 and not data.is_surface_exposed(cell, 0)
		and data.is_surface_exposed(cell, 1), "stacked water exposes only its highest surface")
	data.remove_layer(cell, 0)
	check(data.is_water_layer(cell, 1) and not data.layer_exists(cell, 0),
		"water removal does not invent support or shift higher blocks")
	var snapshot := data.clone_data()
	var path := "user://ocean1016_roundtrip.tres"
	ResourceSaver.save(data, path)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.clone_data() == snapshot, "independent water survives save and reload")
	DirAccess.remove_absolute(path)
	var prefab: LevelPrefab = LevelPrefab.capture(data, data.map_bounds()).prefab
	var target := LevelData.new()
	target.setup_blank(Vector2i(8, 8))
	var stamp := prefab.stamp(target, Vector2i(1, 1), 1)
	check(stamp.error.is_empty(), "independent ocean prefab rotates and validates")
	var old := LevelData.new()
	old.setup_blank(Vector2i.ONE)
	old.format_version = 8
	old.columns = [{"layers": [{"tile_id":"sand", "liquid":{"tile_id":"water","rotation":2}}]}]
	old.ensure_layout()
	check(old.is_solid_layer(Vector2i.ZERO, 0) and old.tile_id(Vector2i.ZERO, 0) == "sand"
		and old.is_water_layer(Vector2i.ZERO, 1), "v8 migration preserves seabed and creates water volume")
	var once := old.clone_data()
	old.ensure_layout()
	check(old.clone_data() == once, "water migration is idempotent")
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT]:
		var center := data.world_layer_center(cell, 1)
		var hit := Picker.raycast(data, center + normal * 4, -normal)
		check(hit.get("block") == Vector3i(2,1,2), "water logical picking " + str(normal))
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = data
	root.add_child(builder)
	await physics_frame
	await physics_frame
	var position := data.world_layer_center(cell, 1)
	var hit := builder.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(position + Vector3.UP * 10, position - Vector3.UP * 10, 1))
	check(hit.is_empty(), "ocean creates no solid top side or bottom collision")
	check(SceneProbe.tags_at(position).has("ocean")
		and SceneProbe.tags_at(data.world_center(cell, 1)).has("water_surface"),
		"underwater and water-surface detection are separate")
	check(builder.generated.find_children("WaterSurface", "MeshInstance3D", true, false).size() == 1
		and builder.generated.find_children("Underwater_*", "MeshInstance3D", true, false).size() > 0,
		"ocean has separate surface and underwater visuals")
	builder.free()
	await physics_frame

func check_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	check(manifest.entries.size() == 31, "all 31 supplied object images are imported")
	for entry: Dictionary in manifest.entries:
		var before := failures.size()
		var path: String = "res://assets/generated/" + entry.id + "/definition.tres"
		var d := load(path) as PlaceableDefinition
		check(d != null and d.validate_asset().is_empty(), "asset loads " + entry.id)
		if d == null:
			continue
		check(FileAccess.get_sha256(entry.original) == entry.source_sha256,
			"original hash " + entry.id)
		check(d.category == entry.category and d.ecosystems == PackedStringArray(entry.ecosystems)
			and d.mechanism == entry.kind and d.preparation.spec_row == entry.spec_row,
			"classification and sheet provenance " + entry.id)
		var image := (load(d.source_image) as Texture2D).get_image()
		check(image.get_size() == Vector2i(entry.output_pixels[0], entry.output_pixels[1])
			and image.detect_alpha() != Image.ALPHA_NONE, "dimensions and transparency " + entry.id)
		var object := AssetFactory.instantiate_asset(d) as SceneMechanism
		check(object != null and object.find_children("SpatialCell_*", "CollisionObject3D", true, false).size()
			== d.spatial_cells.size(), "actual scene has configured cells " + entry.id)
		var data := LevelData.new()
		data.setup_blank(Vector2i(8, 8))
		var cell := Vector2i(2, 2)
		var eco: String = entry.ecosystems[0]
		for y in 8:
			for x in 8:
				data.set_layer(Vector2i(x,y), 0, {"tile_id": "sand" if eco == "desert"
					else "rock" if eco == "rock" else "grass"})
				if eco == "ocean":
					data.set_layer(Vector2i(x,y), 1, {"tile_id":"water"})
					data.set_layer(Vector2i(x,y), 2, {"tile_id":"water"})
					data.set_layer(Vector2i(x,y), 3, {"tile_id":"water"})
		var record := ObjectRules.anchor_record(data, {"id": entry.id, "definition":path,
			"position":data.world_center(cell,0), "yaw":0.0, "scale":1.0})
		if d.mechanism == "vine":
			record = ObjectRules.wall_anchor(data, record, Vector2i(0,0),0,0)
		check(ObjectRules.validate_record(data, record).is_empty(), "valid ecosystem placement " + entry.id)
		if d.mechanism != "vine":
			check(ObjectRules.covered_cells(data, record).size() == d.spatial_cells.size(),
				"exact footprint coverage " + entry.id)
		data.objects.append(record)
		if eco == "ocean":
			check(not ObjectRules.is_hidden(data, record), "water keeps seabed object visible " + entry.id)
			data.remove_layer(cell, 1)
			if d.requires_seabed:
				check(not ObjectRules.support_error(data, record).is_empty(),
					"missing water rejects ocean-only object " + entry.id)
		elif d.mechanism != "vine":
			data.set_layer(cell, 0, {"tile_id":"water"})
			check(not ObjectRules.support_error(data, record).is_empty(),
				"water surface cannot support land object " + entry.id)
		root.add_child(object)
		object.position = Vector3(40, 0, 40)
		if d.mechanism in ["remains", "resource"]:
			var actor := Node3D.new()
			root.add_child(actor)
			actor.set_meta("scene_inventory_capacity", 0)
			check(not object.interact(actor) and not object.collected
				and actor.get_meta("scene_feedback") == "背包已满，无法拾取", "full inventory retains " + entry.id)
			actor.set_meta("scene_inventory_capacity", 20)
			check(object.interact(actor) and object.collected, "collection works " + entry.id)
			actor.free()
		elif d.mechanism == "chest":
			var actor := Node3D.new()
			root.add_child(actor)
			check(object.interact(actor) and object.state == "open" and not object.interact(actor),
				"chest opens once and emits loot " + entry.id)
			actor.free()
		elif d.mechanism == "fruit_tree":
			check(d.spatial_cells.size() == 3 and Vector3(0,0,2) not in d.spatial_cells,
				"fruit-tree collision leaves L-shape corner open " + entry.id)
			object.level_data = data
			object.position = data.world_center(cell, 0)
			var actor := Node3D.new()
			root.add_child(actor)
			check(object.interact(actor) and not object.has_meta("vine_revealed"),
				"interior fruit tree drops food without vine " + entry.id)
			actor.free()
		elif d.mechanism in ["thorns", "quicksand"]:
			check(d.collision == PlaceableDefinition.Collision.NONE,
				"trap allows entering its trigger region " + entry.id)
			var effects := SceneMechanism.effects_at(object.position + Vector3.UP * 0.5)
			check(effects.speed_multiplier < 1 if d.mechanism == "thorns"
				else SceneMechanism.effects_at(object.position + Vector3(0.5,0.5,0)).drift.length() > 0,
				"trap effect active inside " + entry.id)
		object.free()
		results.append({"id":entry.id, "passed": failures.size() == before})
	await check_bubble_effect()
	for node in root.get_children():
		if node is RigidBody3D:
			node.free()
	await physics_frame

func check_bubble_effect() -> void:
	var zone := SurfaceZone.new()
	zone.tags = PackedStringArray(["fluid","ocean"])
	zone.bind_volume(Vector3(8,8,8))
	zone.position = Vector3(40,2,40)
	root.add_child(zone)
	var d := load("res://assets/generated/scene1016_bubbles_1x1/definition.tres")
	var object := AssetFactory.instantiate_asset(d) as SceneMechanism
	object.position = Vector3(40,0,40)
	root.add_child(object)
	var inside := SceneMechanism.effects_at(Vector3(40,1,40))
	var outside := SceneMechanism.effects_at(Vector3(50,1,50))
	check(inside.drift.y > 0 and inside.oxygen > 0 and outside.drift == Vector3.ZERO,
		"bubble rise and oxygen apply only inside ocean trigger")
	zone.free()
	object.free()

func check_movement() -> void:
	for lower in ["fish_tail","water_snake","octopus_leg","goose_foot"]:
		var expected := 5.0 if lower in ["fish_tail","goose_foot"] else 3.0
		check(TerrainMovementRules.speed(lower,"ocean",false) == expected,
			"Excel water-surface speed " + lower)
		check(TerrainMovementRules.speed(lower,"ocean",true) == (0.0 if lower == "goose_foot" else expected),
			"Excel underwater permission " + lower)
	for lower in ["demon_dog_leg","wolf_leg","gerbil_leg","ostrich_leg","kangaroo_leg"]:
		check(TerrainMovementRules.speed(lower,"ocean") == 0.0, "ocean blocks land locomotion " + lower)
