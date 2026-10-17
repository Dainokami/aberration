extends SceneTree

var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	print("STACK CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	check_migration()
	check_prefab()
	await check_geometry()
	check_chunks()
	check_chunk_expansion()
	print("STACKED TERRAIN TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_migration() -> void:
	var path := "res://data/levels/objects_acceptance.tres"
	var original_hash := FileAccess.get_sha256(path)
	var map := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	var needs_shift := map.format_version < 6
	var positions: Array[Vector3] = []
	for record in map.objects:
		positions.append(record["position"])
	map.ensure_layout()
	var snapshot := map.clone_data()
	for i in 5:
		map.ensure_layout()
	check(map.clone_data() == snapshot, "migration is idempotent")
	check(FileAccess.get_sha256(path) == original_hash, "loading v5 never rewrites the source file")
	var shifted := true
	for i in positions.size():
		shifted = shifted and map.objects[i]["position"].is_equal_approx(
			positions[i] + (Vector3.UP * 2 if needs_shift else Vector3.ZERO))
	check(shifted and map.validate().is_empty(), "sample migration respects its saved version and anchors")
	var legacy := LevelData.new()
	legacy.map_size = Vector2i.ONE
	legacy.cells = [{"exists": true, "tile_id": "grass", "height": 2}]
	legacy.objects = [{"id": "v5", "definition": "res://assets/generated/painted_rock/definition.tres",
		"position": Vector3(0, 4, 0), "scale": 1.0, "yaw": 0.0}]
	legacy.ensure_layout()
	check(legacy.layer_exists(Vector2i.ZERO, 0) and legacy.layer_exists(Vector2i.ZERO, 1)
		and legacy.objects[0]["position"].y == 6 and legacy.objects[0]["anchor_layer"] == 2,
		"explicit v5 fixture migrates filled columns and shifts old object heights")
	var output := "user://stacked_roundtrip.tres"
	check(ResourceSaver.save(map, output) == OK, "explicit save writes v6")
	var loaded := ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.clone_data() == snapshot, "v6 reload preserves all layers and anchors")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	var candidate := map.fork_for_edit()
	var cell := map.spawn_cell
	var original := map.column_snapshot(cell)
	candidate.set_layer(cell, 8, {"tile_id": "sand"})
	candidate.remove_layer(cell, 8)
	check(map.column_snapshot(cell) == original, "uncommitted candidate cannot mutate shared columns")
	check(not map.set_attachment(cell, "liquid", {"tile_id": "grass"}).is_empty(),
		"liquid slot rejects a solid material")
	var column := map.column_snapshot(cell)
	check(not map.set_layer(cell, LevelData.MAX_LAYERS, {"tile_id": "rock"}).is_empty()
		and map.column_snapshot(cell) == column, "out-of-range placement is atomic")

func check_prefab() -> void:
	var source := LevelData.new()
	source.setup_blank(Vector2i(3, 2))
	var cell := Vector2i(1, 0)
	source.set_layer(cell, 0, {"tile_id": "grass", "rotation": 0})
	source.set_layer(cell, 1, {"tile_id": "ground_stone", "rotation": 1})
	source.set_layer(cell, 2, {"tile_id": "sand", "rotation": 2})
	source.set_layer(cell, 2, {"tile_id": "water", "rotation": 3})
	source.set_layer(cell, 2, {"tile_id": "decal_corruption", "rotation": 1})
	var capture := LevelPrefab.capture(source, source.map_bounds())
	var prefab: LevelPrefab = capture["prefab"]
	var destination := LevelData.new()
	destination.setup_blank(Vector2i(8, 8))
	for turns in 4:
		var result := prefab.stamp(destination, Vector2i(2, 2), turns)
		check(result["error"].is_empty(), "stacked prefab rotation %d validates" % turns)
		if not result["error"].is_empty():
			continue
		var stamped := LevelData.new()
		stamped.restore_data(result["snapshot"])
		var target := Vector2i(2, 2) + prefab.rotate_cell(cell, turns)
		check(stamped.layer_count(target) == 3
			and stamped.solid_tile_id(target, 0) == "grass"
			and stamped.solid_tile_id(target, 1) == "ground_stone"
			and stamped.solid_tile_id(target, 2) == "sand"
			and stamped.get_layer(target, 1)["rotation"] == posmod(1 + turns, 4)
			and stamped.get_attachment(target, "liquid")["rotation"] == posmod(3 + turns, 4)
			and stamped.get_attachment(target, "overlay")["rotation"] == posmod(1 + turns, 4),
			"prefab preserves and rotates every block and attachment %d" % turns)
	check(not destination.cell_exists(Vector2i(2, 2)), "prefab candidate leaves destination unchanged")

func check_geometry() -> void:
	var map := LevelData.new()
	map.setup_blank(Vector2i(2, 1))
	var cell := Vector2i.ZERO
	map.set_layer(cell, 0, {"tile_id": "grass"})
	map.set_layer(cell, 1, {"tile_id": "rock", "rotation": 2})
	map.set_layer(cell, 2, {"tile_id": "sand"})
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = map
	root.add_child(builder)
	var before := map.clone_data()
	var boundary_shapes := {}
	for child in builder.generated.get_children():
		if not child.get_meta("terrain_side", false):
			continue
		var layer: int = child.get_meta("terrain_layer")
		var top_points: Array[String] = []
		var bottom_points: Array[String] = []
		for vertex: Vector3 in child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var key := "%.4f,%.4f" % [vertex.x, vertex.z]
			if is_equal_approx(vertex.y, map.surface_y(layer)):
				if key not in top_points:
					top_points.append(key)
			else:
				if key not in bottom_points:
					bottom_points.append(key)
		top_points.sort()
		bottom_points.sort()
		boundary_shapes[layer] = {"top": top_points, "bottom": bottom_points}
	check(boundary_shapes[0]["top"] == boundary_shapes[1]["bottom"]
		and boundary_shapes[1]["top"] == boundary_shapes[2]["bottom"],
		"different material corner radii share exact vertical seams")
	builder.set_slice_layer(1)
	check(map.clone_data() == before, "slice viewing never changes saved data")
	await physics_frame
	await physics_frame
	var center := map.world_center(cell)
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 10, center - Vector3.UP * 10)
	var hit := builder.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit["collider"].get_meta("terrain_layer") == 1
		and absf(hit["position"].y - 4.0) < 0.01, "slice picking hits B while C is hidden")
	builder.set_slice_layer(-1)
	await physics_frame
	await physics_frame
	hit = builder.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit["collider"].get_meta("terrain_layer") == 2
		and absf(hit["position"].y - 6.0) < 0.01, "leaving slice restores C collision")
	map.set_layer(cell, 2, {"tile_id": "decal_corruption"})
	builder.rebuild_cells([cell])
	var overlay_found := false
	for child in builder.generated.get_children():
		if child.get_meta("terrain_overlay", false):
			overlay_found = child.material_override.get_shader_parameter("has_mask")
	check(overlay_found and map.solid_tile_id(cell) == "sand",
		"masked overlay renders separately from the solid surface")
	var neighbor := Vector2i(1, 0)
	map.set_layer(neighbor, 0, {"tile_id": "grass"})
	var high_outline := TerrainEdgeBuilder._top_polygon(
		map, cell, TileRegistry.find("sand"), 4)
	var low_outline := TerrainEdgeBuilder._top_polygon(
		map, neighbor, TileRegistry.find("grass"), 4)
	check(Vector2(1, -1) in high_outline and Vector2(1, 1) in high_outline
		and Vector2(-1, -1) in low_outline and Vector2(-1, 1) in low_outline,
		"unequal-height columns meet flush along both ends of their shared edge")
	map.set_layer(neighbor, 0, {"tile_id": "water"})
	check(TerrainEdgeBuilder._top_polygon(map, neighbor, TileRegistry.find("water"), 4)
		== low_outline, "liquid outline matches its solid support")
	builder.rebuild_cells([neighbor])
	await physics_frame
	await physics_frame
	query = PhysicsRayQueryParameters3D.create(Vector3(-0.04, 1, 10),
		Vector3(-0.04, 1, -10))
	hit = builder.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and absf(hit["position"].z - 1.0) < 0.01,
		"lower layer has no collision crack next to a rounded higher column")
	builder.free()
	await physics_frame

func check_chunks() -> void:
	var map := LevelData.new()
	map.setup_blank(Vector2i(32, 16))
	for y in map.map_size.y:
		for x in map.map_size.x:
			map.set_layer(Vector2i(x, y), 0,
				{"tile_id": "grass" if x % 4 < 2 else "rock"})
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = map
	root.add_child(builder)
	var remote: Array = builder._chunk_nodes[Vector2i(3, 1)].duplicate()
	var remote_ids: Array[int] = []
	for node: Node in remote:
		remote_ids.append(node.get_instance_id())
	var cell := Vector2i(7, 7)
	map.set_layer(cell, 2, {"tile_id": "sand"})
	var started := Time.get_ticks_usec()
	builder.rebuild_cells([cell])
	var elapsed := Time.get_ticks_usec() - started
	var current_ids: Array[int] = []
	for node: Node in builder._chunk_nodes[Vector2i(3, 1)]:
		current_ids.append(node.get_instance_id())
	check(current_ids == remote_ids, "terrain edit preserves untouched chunk nodes")
	var incremental := geometry_signature(builder)
	builder.rebuild()
	check(geometry_signature(builder) == incremental,
		"chunk-boundary height edit equals a full geometry rebuild")
	check(elapsed < 250000, "four-chunk structural refresh under 250ms (%dus)" % elapsed)
	map.set_layer(Vector2i(8, 8), 0, {"tile_id": "ground_forest", "rotation": 3})
	check(builder.refresh_blend_cells([Vector2i(8, 8)]), "boundary splat refresh uses existing textures")
	var incremental_pixels := {}
	for key in builder._blend_resources:
		var blend: Dictionary = builder._blend_resources[key]
		incremental_pixels[key] = [
			blend["index_image"].get_data(), blend["weight_image"].get_data(),
			blend["rotation_image"].get_data()]
	builder.rebuild()
	var pixels_match := true
	for key in builder._blend_resources:
		var blend: Dictionary = builder._blend_resources[key]
		pixels_match = pixels_match and incremental_pixels[key] == [
			blend["index_image"].get_data(), blend["weight_image"].get_data(),
			blend["rotation_image"].get_data()]
	check(pixels_match, "incremental chunk halo weights equal full rebuilt textures")
	builder.free()

func check_chunk_expansion() -> void:
	var map := LevelData.new()
	map.setup_blank(Vector2i(32, 32))
	for y in map.map_size.y:
		for x in map.map_size.x:
			map.set_layer(Vector2i(x, y), 0,
				{"tile_id": "grass" if x % 4 < 2 else "rock"})
	var builder := TerrainBuilder.new()
	builder.level_data = map
	root.add_child(builder)
	var world_center := map.world_center(Vector2i(12, 12))
	# Positive/negative origins, partial chunks and a new halo around old borders.
	for cell in [Vector2i(32, 12), Vector2i(-1, 12), Vector2i(12, -1),
			Vector2i(12, 32), Vector2i(35, 12)]:
		var before := map.clone_data()
		var generated := builder.generated
		var remote: Array = builder._chunk_nodes[Vector2i(1, 1)].duplicate()
		map.expand_to_include(Rect2i(cell, Vector2i.ONE))
		map.set_layer(cell, 0, {"tile_id": "sand"})
		builder.rebuild_cells([cell])
		var retained := generated == builder.generated
		for node in remote:
			retained = retained and is_instance_valid(node) and node.is_inside_tree()
		check(retained, "edge paint preserves interior meshes and collision nodes %s" % cell)
		check(map.world_center(Vector2i(12, 12)) == world_center,
			"edge growth keeps terrain world coordinates %s" % cell)
		_check_incremental_matches_full(builder, "expansion %s" % cell)
		# Bounds contraction must remove outside chunks and shrink their halos/grid.
		map.restore_data(before)
		builder.rebuild_cells([cell])
		_check_incremental_matches_full(builder, "contraction %s" % cell)
		# Grow again so the next iteration also exercises partial existing chunks.
		map.expand_to_include(Rect2i(cell, Vector2i.ONE))
		map.set_layer(cell, 0, {"tile_id": "sand"})
		builder.rebuild_cells([cell])
	builder.free()

func _check_incremental_matches_full(builder: TerrainBuilder, label: String) -> void:
	var geometry := geometry_signature(builder)
	var collision := _collision_signature(builder)
	var grid := _grid_signature(builder)
	var blends := _blend_signature(builder)
	builder.rebuild()
	check(geometry_signature(builder) == geometry, label + " geometry equals full rebuild")
	check(_collision_signature(builder) == collision, label + " collision equals full rebuild")
	check(_grid_signature(builder) == grid, label + " grid bounds equal full rebuild")
	check(_blend_signature(builder) == blends, label + " texture halos equal full rebuild")

func _blend_signature(builder: TerrainBuilder) -> Dictionary:
	var result := {}
	for key in builder._blend_resources:
		var blend: Dictionary = builder._blend_resources[key]
		result[key] = [blend["region"], blend["index_image"].get_data(),
			blend["weight_image"].get_data(), blend["rotation_image"].get_data()]
	return result

func _grid_signature(builder: TerrainBuilder) -> Array[String]:
	var result: Array[String] = []
	for node in builder.generated.get_children():
		if node.has_meta("terrain_grid"):
			result.append("%s|%s" % [node.position, node.mesh.size])
	result.sort()
	return result

func _collision_signature(builder: TerrainBuilder) -> Array[String]:
	var result: Array[String] = []
	for node in builder.generated.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = node.shape
		var geometry: Variant = shape.points if shape is ConvexPolygonShape3D else shape.get_debug_mesh().get_faces()
		result.append("%s|%s|%s" % [node.global_transform, node.disabled, hash(geometry)])
	result.sort()
	return result

func geometry_signature(builder: TerrainBuilder) -> Array[String]:
	var result: Array[String] = []
	for node in builder.generated.get_children():
		if node is MeshInstance3D:
			result.append("%s|%s|%s|%s" % [node.get_meta("terrain_chunk", ""),
				node.get_meta("terrain_layer", ""), node.get_meta("terrain_tile", ""),
				hash(node.mesh.get_faces())])
	result.sort()
	return result
