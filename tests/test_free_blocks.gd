extends SceneTree

const ROCK := "res://assets/generated/painted_rock/definition.tres"
const DETAILS := "res://data/details/painted_upright.tres"
const Picker := preload("res://addons/terrain_editor/block_picker.gd")
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	print("FREE BLOCK CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	check_data()
	check_covered_content()
	check_picking()
	await check_rendering()
	await check_lower_stairs()
	await check_large_map()
	print("FREE BLOCK FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_data() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(3, 3))
	var cell := Vector2i(1, 1)
	check(data.set_layer(cell, 6, {"tile_id": "rock"}).is_empty(), "place floating block")
	check(data.layer_exists(cell, 6) and not data.layer_exists(cell, 0)
		and not data.layer_exists(cell, 5), "floating block never fills supports")
	data.set_layer(cell, 2, {"tile_id": "grass", "rotation": 1})
	data.set_layer(cell, 3, {"tile_id": "sand"})
	check(data.remove_layer(cell, 3).is_empty() and data.layer_exists(cell, 6)
		and data.layer_exists(cell, 2) and not data.layer_exists(cell, 3),
		"erase middle block without moving other heights")
	data.set_attachment(cell, "liquid", {"tile_id": "water"}, 2)
	data.set_attachment(cell, "overlay", {"tile_id": "decal_corruption"}, 2)
	var before := data.clone_data()
	var fork := data.fork_for_edit()
	fork.set_layer(cell, 3, {"tile_id": "rock"})
	check(data.clone_data() == before, "edits never mutate shared columns")
	check(not fork.is_surface_exposed(cell, 2)
		and data.is_water_layer(cell, 3)
		and fork.surface_view(2).cell_exists(cell) == false,
		"solid cover hides seabed while original fork retains independent water")
	fork.remove_layer(cell, 3)
	check(fork.surface_view(2).tile_id(cell) == "grass"
		and fork.surface_view(2).overlay_tile_id(cell) == "decal_corruption"
		and fork.surface_view(6).tile_id(cell) == "rock",
		"separated exposed surfaces keep independent materials")
	var capture := LevelPrefab.capture(data, data.map_bounds())
	var destination := LevelData.new()
	destination.setup_blank(Vector2i(8, 8))
	var prefab: LevelPrefab = capture["prefab"]
	var stamped := prefab.stamp(destination, Vector2i(2, 2), 1)
	check(stamped["error"].is_empty(), "sparse prefab validates")
	if stamped["error"].is_empty():
		destination.restore_data(stamped["snapshot"])
		var target := Vector2i(2, 2) + prefab.rotate_cell(cell, 1)
		check(destination.get_layer(target, 2).get("rotation") == 2
			and destination.is_water_layer(target, 3)
			and destination.get_layer(target, 3).get("rotation") == 1
			and not destination.layer_exists(target, 4),
			"prefab rotation preserves water blocks and air gaps")
	var legacy := LevelData.new()
	legacy.setup_blank(Vector2i.ONE)
	legacy.columns = [{"layers": [{"tile_id": "grass"}, {"tile_id": "rock"}],
		"liquid": {"tile_id": "water", "rotation": 3}, "overlay": {}}]
	legacy.format_version = 7
	legacy.ensure_layout()
	var migrated := legacy.clone_data()
	legacy.ensure_layout()
	check(legacy.layer_exists(Vector2i.ZERO, 0) and legacy.layer_exists(Vector2i.ZERO, 1)
		and legacy.get_attachment(Vector2i.ZERO, "liquid", 1).get("rotation") == 3
		and migrated == legacy.clone_data(), "v7 migration preserves geometry and water exactly once")
	var output := "user://free_blocks_roundtrip.tres"
	check(ResourceSaver.save(data, output) == OK, "sparse data saves")
	var loaded := ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.clone_data() == before, "roundtrip preserves empty heights and attachments")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))

func check_covered_content() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(4, 4))
	var cell := Vector2i(1, 1)
	data.set_layer(cell, 0, {"tile_id": "grass"})
	var object := ObjectRules.anchor_record(data, {"id": "root", "definition": ROCK,
		"position": data.world_center(cell, 0), "scale": 1.0, "yaw": 0.0})
	data.objects.append(object)
	var set := load(DETAILS) as DetailSet
	var detail := DetailRules.make_record(data, DETAILS, str(set.variants[0]["id"]),
		data.world_center(cell, 0), "detail")
	data.details.append(detail)
	var position: Vector3 = object["position"]
	data.set_layer(cell, 1, {"tile_id": "rock"})
	check(ObjectRules.validate_all(data).is_empty() and DetailRules.validate_all(data).is_empty(),
		"covered records remain valid saved data")
	check(ObjectRules.is_hidden(data, object) and DetailRules.is_hidden(data, detail),
		"immediate cover hides object and detail")
	check(object["position"] == position and int(object["anchor_layer"]) == 0,
		"adding cover does not lift existing content")
	data.remove_layer(cell, 1)
	data.set_layer(cell, 3, {"tile_id": "rock"})
	check(not ObjectRules.is_hidden(data, object) and not DetailRules.is_hidden(data, detail),
		"air gap leaves lower surface content visible")
	data.set_layer(cell, 1, {"tile_id": "rock"})
	var child := ObjectRules.object_anchor(data, {"id": "child", "definition": ROCK,
		"scale": 1.0, "yaw": 0.0}, "root", position + Vector3.UP * 2)
	data.objects.push_front(child)
	check(ObjectRules.is_hidden(data, child), "host attachments inherit visibility in any storage order")

func check_picking() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(4, 4))
	var cell := Vector2i(1, 1)
	data.set_layer(cell, 0, {"tile_id": "grass"})
	data.set_layer(cell, 3, {"tile_id": "rock"})
	var center := data.world_layer_center(cell, 3)
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var hit := Picker.raycast(data, center + normal * 3.0, -normal)
		check(not hit.is_empty() and hit["block"] == Vector3i(1, 3, 1)
			and hit["normal"] == Vector3i(normal), "six-face logical picking %s" % normal)
	var air := Picker.raycast(data, Vector3(-12, 4, center.z), Vector3.RIGHT)
	check(air.is_empty(), "ray passes through empty height without phantom support")
	var sliced := Picker.raycast(data, center + Vector3.UP * 10, Vector3.DOWN, 1)
	check(sliced.get("layer") == 0, "slice over air picks the actual lower block")
	data.expand_to_include(Rect2i(-2, -1, 1, 1))
	data.set_layer(Vector2i(-2, -1), 5, {"tile_id": "sand"})
	var negative := Picker.raycast(data, data.world_center(Vector2i(-2, -1), 5) \
		+ Vector3.UP * 3, Vector3.DOWN)
	check(negative.get("block") == Vector3i(-2, 5, -1), "negative map coordinates retain precise voxel hits")

func check_rendering() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(4, 4))
	var cell := Vector2i(1, 1)
	var next := Vector2i(2, 1)
	var prop_cell := Vector2i(1, 2)
	data.set_layer(cell, 0, {"tile_id": "grass"})
	data.set_layer(cell, 1, {"tile_id": "water"})
	data.set_layer(cell, 0, {"tile_id": "decal_corruption"})
	data.set_layer(cell, 3, {"tile_id": "rock"})
	data.set_layer(next, 0, {"tile_id": "rock"})
	data.set_layer(next, 3, {"tile_id": "grass"})
	data.set_layer(prop_cell, 0, {"tile_id": "grass"})
	data.objects.append(ObjectRules.anchor_record(data, {"id": "visible_prop", "definition": ROCK,
		"position": data.world_center(prop_cell, 0), "scale": 1.0, "yaw": 0.0}))
	var set := load(DETAILS) as DetailSet
	data.details.append(DetailRules.make_record(data, DETAILS, str(set.variants[0]["id"]),
		data.world_center(prop_cell, 0), "visible_detail"))
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = data
	root.add_child(builder)
	var top_heights: Array[int] = []
	var overlay_count := 0
	var air_geometry := false
	for node in builder.generated.get_children():
		if node.has_meta("terrain_cells") and cell in node.get_meta("terrain_cells") \
				and not node.get_meta("terrain_overlay", false):
			top_heights.append(int(node.get_meta("terrain_layer")))
		if node.get_meta("terrain_overlay", false):
			overlay_count += 1
		if node.get_meta("terrain_side", false) and int(node.get_meta("terrain_layer")) in [1, 2]:
			air_geometry = true
	check(0 in top_heights and 3 in top_heights and overlay_count == 1 and not air_geometry,
		"all exposed heights render while air produces no walls")
	var low_blend: Dictionary = builder._blend_resources[Vector3i(0, 0, 0)]
	var high_blend: Dictionary = builder._blend_resources[Vector3i(0, 3, 0)]
	check(low_blend["index_image"].get_data() != high_blend["index_image"].get_data(),
		"same cell at different heights has independent blend raster pixels")
	await physics_frame
	await physics_frame
	var center := data.world_center(cell, 0)
	var space := builder.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(center.x, 4, center.z), Vector3(center.x, 10, center.z)))
	check(not hit.is_empty() and is_equal_approx(hit["position"].y, 6.0),
		"floating underside has physical collision at the actual block bottom")
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(-10, 4, center.z), Vector3(10, 4, center.z)))
	check(hit.is_empty(), "physics ray traverses the air gap")
	builder.set_slice_layer(1)
	check(builder.generated.get_node("SliceCaps").get_child_count() == 0,
		"slice over air generates no fake caps or collisions")
	builder.set_slice_layer(-1)
	var records := [data.objects.duplicate(true), data.details.duplicate(true)]
	data.set_layer(cell, 1, {"tile_id": "sand"})
	data.set_layer(prop_cell, 1, {"tile_id": "rock"})
	builder.rebuild_cells([cell, prop_cell])
	var hidden := true
	for node in builder.generated.get_children():
		if node.has_meta("object_id") or node.get_meta("terrain_overlay", false):
			hidden = false
	check(hidden and builder.detail_renderer.groups.is_empty()
		and data.objects == records[0] and data.details == records[1],
		"cover avoids instantiating objects, details and overlays without deleting records")
	data.remove_layer(cell, 1)
	data.remove_layer(prop_cell, 1)
	builder.rebuild_cells([cell, prop_cell])
	var restored := false
	for node in builder.generated.get_children():
		if node.get_meta("object_id", "") == "visible_prop":
			restored = true
	check(restored and not builder.detail_renderer.groups.is_empty(),
		"uncover rebuild restores the same object and detail instances")
	builder.free()
	await physics_frame

func check_lower_stairs() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(2, 1))
	var low := Vector2i.ZERO
	var high := Vector2i(1, 0)
	data.set_layer(low, 2, {"tile_id": "grass"})
	data.set_layer(high, 3, {"tile_id": "rock"})
	data.set_layer(low, 5, {"tile_id": "grass"})
	data.set_layer(high, 6, {"tile_id": "rock"})
	check(data.can_place_stair(low, 1, 2).is_empty(),
		"stairs can connect lower exposed surfaces under separate floating blocks")
	data.stairs.append({"cell": low, "direction": 1, "layer": 2})
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	root.add_child(builder)
	check(builder.generated.get_node("StairRamp").position.y == 6.0,
		"lower stair geometry uses its saved height instead of the highest column")
	builder.set_slice_layer(2)
	await physics_frame
	await physics_frame
	var center := data.world_center(low, 2)
	var space := builder.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 20, center - Vector3.UP * 10))
	check(not hit.is_empty() and is_equal_approx(hit["position"].y, 6.0)
		and hit["collider"].get_meta("slice_cap", false),
		"slicing below a stair reveals its real low support with a marked cap")
	center = data.world_center(high, 2)
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 20, center - Vector3.UP * 10))
	check(hit.is_empty(), "stair slicing never creates a cap in its empty high support column")
	builder.free()
	await physics_frame

func check_large_map() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(599, 599))
	var anchor := Vector2i(300, 300)
	var world := data.world_center(anchor, 0)
	check(data.expand_to_include(Rect2i(599, 599, 1, 1)).is_empty()
		and data.map_size == Vector2i(600, 600),
		"both positive axes reach 600 cells despite optional expansion padding")
	check(not data.expand_to_include(Rect2i(600, 300, 1, 1)).is_empty()
		and not data.expand_to_include(Rect2i(300, 600, 1, 1)).is_empty(),
		"both axes reject only coordinates genuinely beyond 600 cells")
	data.resize_bounds(Rect2i(0, 0, 599, 599))
	check(data.expand_to_include(Rect2i(-1, -1, 1, 1)).is_empty()
		and data.map_origin == Vector2i(-1, -1) and data.map_size == Vector2i(600, 600)
		and data.world_center(anchor, 0) == world,
		"negative axes reach 600 cells without shifting existing world coordinates")
	for cell in [Vector2i(-1, -1), anchor, Vector2i(598, 598)]:
		data.set_layer(cell, 0, {"tile_id": "grass"})
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	root.add_child(builder)
	check(builder._chunk_nodes.size() == 3, "600x600 sparse map builds only occupied chunks")
	var other := Vector2i(300, 301)
	data.objects.append(ObjectRules.anchor_record(data, {"id": "retained", "definition": ROCK,
		"position": data.world_center(anchor, 0), "scale": 1.0, "yaw": 0.0}))
	builder.refresh_objects()
	var object: Node3D = builder._object_nodes["retained"]
	data.set_layer(other, 0, {"tile_id": "grass"})
	builder.rebuild_cells([other])
	check(is_instance_valid(object) and builder._object_nodes["retained"] == object,
		"terrain edit retains unaffected object nodes rather than recreating them")
	var nodes: Array = builder._chunk_nodes[Vector2i(37, 37)].duplicate()
	data.objects.clear()
	builder.refresh_objects()
	var retained := true
	for node in nodes:
		retained = retained and is_instance_valid(node)
	check(retained and builder._object_nodes.is_empty(), "object deletion never rebuilds terrain chunks")
	builder.free()
	await physics_frame
