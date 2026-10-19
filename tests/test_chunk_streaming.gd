extends SceneTree

var failures: Array[String] = []
var reports: Array[Dictionary] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("STREAM CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func fixture(size: int) -> LevelData:
	var map := LevelData.new()
	map.setup_blank(Vector2i(size, size))
	for y in size:
		for x in size:
			map.columns[y * size + x] = {"layers": [{"tile_id": "grass" if x < size / 2 else "rock"}]}
	map.spawn_cell = Vector2i(size / 2, size / 2)
	map.spawn_layer = 0
	return map

func drain(builder: TerrainBuilder) -> void:
	var remaining := 3000
	while (not builder.chunk_stream.pending.is_empty() or is_instance_valid(builder.chunk_stream.job_root)
			or remaining > 2990) and remaining > 0:
		builder.chunk_stream.step(builder, 0.16)
		remaining -= 1
	for i in 400:
		var previous := builder._chunk_nodes.size()
		builder.chunk_stream.step(builder, 0.16)
		if previous == builder._chunk_nodes.size():
			break
	await physics_frame
	check(remaining > 0, "stream queue finishes")

func run() -> void:
	var map := fixture(200)
	var complete := TerrainBuilder.new()
	complete.level_data = map
	complete.chunk_loading = false
	complete.show_grid = false
	var start := Time.get_ticks_usec()
	root.add_child(complete)
	var full_ms := (Time.get_ticks_usec() - start) / 1000.0
	var full_nodes := complete.find_children("*", "", true, false).size()
	reports.append({"scenario": "200_complete", "initial_ms": full_ms,
		"nodes": full_nodes, "chunks": complete._chunk_nodes.size()})
	complete.free()
	await physics_frame

	var builder := TerrainBuilder.new()
	builder.level_data = map
	builder.show_grid = false
	start = Time.get_ticks_usec()
	root.add_child(builder)
	var stream_ms := (Time.get_ticks_usec() - start) / 1000.0
	check(builder.is_streaming() and builder._chunk_nodes.size() <= 4,
		"200 map initially builds only spawn support")
	check(stream_ms < full_ms * 0.3, "stream startup substantially cheaper than complete build")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	var focus := map.world_center(map.spawn_cell)
	camera.position = focus + Vector3(0, 38, 24)
	camera.look_at(focus)
	builder.follow_stream_camera(camera)
	builder.chunk_stream.select(builder, true)
	check(builder.chunk_stream.view_margin_cells == TerrainChunkStream.CELL_MARGIN,
		"non-runtime camera keeps original streaming margin")
	await drain(builder)
	check(builder._chunk_nodes.size() < 80, "camera working set is bounded")
	check(builder.stream_cell_loaded(map.spawn_cell), "camera focus ground loaded")
	check(not builder.stream_cell_loaded(Vector2i(5, 5)), "distant ground actually unloaded")
	check(builder.find_children("*", "PhysicsBody3D", true, false).size()
		== builder._chunk_nodes.size(), "streamed collision bodies use chunk batches")
	reports.append({"scenario": "200_stream", "initial_ms": stream_ms,
		"nodes": builder.find_children("*", "", true, false).size(),
		"chunks": builder._chunk_nodes.size(), "peak_chunk_ms": builder.chunk_stream.peak_build_usec / 1000.0})
	var first_chunk := TerrainChunkStream.chunk_for(map.spawn_cell)
	var old_nodes: Array = builder._chunk_nodes[first_chunk].duplicate()
	var remote := Vector2i(12, 12)
	map.set_layer(remote, 2, {"tile_id": "sand"})
	builder.rebuild_cells([remote])
	check(not builder.stream_cell_loaded(remote), "editing unloaded cell does not instantiate remote terrain")
	focus = map.world_center(remote, 2)
	camera.position = focus + Vector3(0, 38, 24)
	camera.look_at(focus)
	builder.chunk_stream.select(builder, true)
	await drain(builder)
	check(builder.stream_cell_loaded(remote), "camera teleport loads new location")
	var removed := true
	for node in old_nodes:
		removed = removed and not is_instance_valid(node)
	check(removed, "moving away releases old terrain and physics nodes")
	var hit := builder.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(focus + Vector3.UP * 2, focus - Vector3.UP))
	check(not hit.is_empty(), "newly loaded edited floating floor has real collision")
	map.set_layer(remote, 3, {"tile_id": "sand"})
	builder.rebuild_cells([remote])
	builder.set_slice_layer(2)
	await physics_frame
	check(is_instance_valid(builder._slice_caps), "streamed slice builds caps")
	var bounded_caps := true
	for cap in builder._slice_caps.get_children():
		for cell in cap.get_meta("terrain_cells", []):
			bounded_caps = bounded_caps and builder.stream_cell_loaded(cell)
	check(bounded_caps, "slice creates no remote fake terrain")
	builder.set_slice_layer(-1)
	var record := ObjectRules.anchor_record(map, {"id": "stream_chest",
		"definition": "res://assets/generated/scene1016_chest_1538/definition.tres",
		"position": map.world_center(remote, 3), "yaw": 0.0, "scale": 1.0})
	map.objects.append(record)
	builder.refresh_objects()
	var chest: GameplayProp = builder._object_nodes.get("stream_chest")
	check(chest != null, "prop loads with its chunk")
	if chest != null:
		var resource_cell := remote + Vector2i(2, 0)
		var resource_record := ObjectRules.anchor_record(map, {"id": "stream_resource",
			"definition": "res://assets/generated/scene1016_resource_1x1/definition.tres",
			"position": map.world_center(resource_cell), "yaw": 0.0, "scale": 1.0})
		map.objects.append(resource_record)
		var detail_cell := remote + Vector2i(3, 0)
		map.details.append({"id": "stream_detail", "set": "res://data/details/painted_flat.tres",
			"variant": "detail_02", "position": map.world_center(detail_cell),
			"anchor_cell": detail_cell, "anchor_layer": 0, "scale": 1.0, "yaw": 0.0})
		builder.refresh_objects()
		builder.rebuild_details()
		var resource: SceneMechanism = builder._object_nodes["stream_resource"]
		var actor := Node3D.new()
		root.add_child(actor)
		check(chest.interact(actor), "open actual streamed chest")
		await create_timer(0.4).timeout
		var lid := chest.get_node_or_null("ChestLid") as Node3D
		var lid_pose := lid.rotation if lid != null else Vector3.ZERO
		var drops: Array = builder.generated.get_children().filter(func(node):
			return node.get_meta("stream_source_id", "") == "stream_chest")
		check(drops.size() == 3, "chest generates exactly three pickups")
		check(resource.interact(actor), "collect streamed resource")
		var details := builder.detail_renderer.groups.values().duplicate()
		check(not details.is_empty(), "nearby detail batch loads")
		actor.free()
		camera.position = map.world_center(map.spawn_cell) + Vector3(0, 38, 24)
		camera.look_at(map.world_center(map.spawn_cell))
		builder.chunk_stream.select(builder, true)
		await drain(builder)
		check(not is_instance_valid(chest), "remote prop is freed")
		check(not is_instance_valid(resource), "collected remote resource releases its node")
		check(details.all(func(node): return not is_instance_valid(node)), "remote detail batches released")
		check(drops.all(func(node): return is_instance_valid(node) and not node.is_inside_tree()),
			"unloaded chest pickups suspend outside scene")
		camera.position = focus + Vector3(0, 38, 24)
		camera.look_at(focus)
		builder.chunk_stream.select(builder, true)
		await drain(builder)
		chest = builder._object_nodes.get("stream_chest")
		check(chest != null and chest.state == "open", "chest remains open after unload and reload")
		lid = chest.get_node_or_null("ChestLid") as Node3D if chest != null else null
		check(lid != null and lid.rotation == lid_pose, "opened chest hinge pose survives reload")
		check(drops.all(func(node): return is_instance_valid(node) and node.get_parent() == builder.generated),
			"same chest pickups resume without duplication")
		resource = builder._object_nodes.get("stream_resource")
		check(resource != null and resource.collected and not resource.visible,
			"collected resource remains collected after reload")
		check(not builder.detail_renderer.groups.is_empty(), "detail batch returns with original records")
	check(map.objects.size() == 2 and map.is_solid_layer(remote, 3),
		"streaming retains complete authored map")
	var pushed := ObjectRules.anchor_record(map, {"id": "stream_pushed",
		"definition": "res://assets/generated/demo_rock/definition.tres",
		"position": map.world_center(remote + Vector2i(4, 0)), "yaw": 0.0, "scale": 1.0})
	map.objects.append(pushed)
	builder.refresh_objects()
	var push_prop: AffordanceProp = builder._affordance_nodes.get("stream_pushed")
	check(push_prop != null, "pushable prop has runtime movement adapter")
	if push_prop != null:
		var moved_position := map.world_center(map.spawn_cell)
		push_prop.position = moved_position
		push_prop.host.position = moved_position
		camera.position = moved_position + Vector3(0, 38, 24)
		camera.look_at(moved_position)
		builder.chunk_stream.select(builder, true)
		await drain(builder)
		check(builder._object_nodes.has("stream_pushed")
			and builder._object_nodes["stream_pushed"].position == moved_position,
			"moved prop stays loaded at new position")
		camera.position = focus + Vector3(0, 38, 24)
		camera.look_at(focus)
		builder.chunk_stream.select(builder, true)
		await drain(builder)
		check(not builder._object_nodes.has("stream_pushed"),
			"original anchor cannot resurrect prop moved to unloaded chunk")
		camera.position = moved_position + Vector3(0, 38, 24)
		camera.look_at(moved_position)
		builder.chunk_stream.select(builder, true)
		await drain(builder)
		check(builder._object_nodes.has("stream_pushed")
			and builder._object_nodes["stream_pushed"].position == moved_position,
			"moved prop reloads from its current chunk")
	check(map.expand_to_include(Rect2i(-1, 10, 1, 1)).is_empty(), "streamed map expands to negative coordinate")
	map.set_layer(Vector2i(-1, 10), 0, {"tile_id": "grass"})
	builder.rebuild_cells([Vector2i(-1, 10)])
	focus = map.world_center(Vector2i(-1, 10))
	camera.position = focus + Vector3(0, 38, 24)
	camera.look_at(focus)
	builder.chunk_stream.select(builder, true)
	await drain(builder)
	check(builder.stream_cell_loaded(Vector2i(-1, 10)), "camera loads newly expanded negative chunk")
	camera.free()
	builder.free()
	await physics_frame
	var generator := WorldGenerator.new()
	var recipe := WorldGenConfig.new()
	recipe.width = 200
	recipe.height = 200
	check(generator.prepare(recipe).is_empty(), "200 mixed generation prepares")
	start = Time.get_ticks_usec()
	var output := generator.generate()
	var generation_ms := (Time.get_ticks_usec() - start) / 1000.0
	check(str(output.error).is_empty(), "200 mixed map generates")
	if output.has("data"):
		builder = TerrainBuilder.new()
		builder.level_data = output.data
		builder.show_grid = false
		start = Time.get_ticks_usec()
		root.add_child(builder)
		await drain(builder)
		check(builder.is_streaming() and builder._chunk_nodes.size() < 100,
			"generated mixed map with real props also streams")
		reports.append({"scenario": "200_generated_stream", "generation_ms": generation_ms,
			"load_and_drain_ms": (Time.get_ticks_usec() - start) / 1000.0,
			"nodes": builder.find_children("*", "", true, false).size(),
			"chunks": builder._chunk_nodes.size(), "props": builder._object_nodes.size(),
			"peak_total_ms": builder.chunk_stream.peak_total_usec / 1000.0})
		builder.free()
		await physics_frame
	var huge := fixture(600)
	builder = TerrainBuilder.new()
	builder.level_data = huge
	builder.show_grid = false
	start = Time.get_ticks_usec()
	root.add_child(builder)
	reports.append({"scenario": "600_stream", "initial_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"nodes": builder.find_children("*", "", true, false).size(), "chunks": builder._chunk_nodes.size()})
	check(builder._chunk_nodes.size() <= 4 and huge.columns.size() == 360000,
		"600 map also loads only initial support while retaining complete data")
	camera = Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	focus = huge.world_center(huge.spawn_cell)
	camera.position = focus + Vector3(0, 38, 24)
	camera.look_at(focus)
	builder.follow_stream_camera(camera)
	builder.chunk_stream.select(builder, true)
	await drain(builder)
	check(builder._chunk_nodes.size() < 80, "600 camera working set matches 200 camera scale")
	focus = huge.world_center(Vector2i(500, 500))
	camera.position = focus + Vector3(0, 38, 24)
	camera.look_at(focus)
	builder.chunk_stream.select(builder, true)
	await drain(builder)
	check(builder.stream_cell_loaded(Vector2i(500, 500))
		and not builder.stream_cell_loaded(huge.spawn_cell), "600 camera teleport replaces rather than accumulates chunks")
	var monster := load("res://data/monsters/wolf.tres") as MonsterDefinition
	var nav := EncounterNavigation.new()
	var reference := EncounterNavigation.new()
	nav.build_incremental(huge, monster, builder._chunk_nodes)
	reference.build(huge, monster, builder._chunk_nodes)
	var iterations := 0
	while nav.building and iterations < 10000:
		nav.step_build()
		iterations += 1
	var edges_match := true
	for id in reference.surfaces:
		var actual := nav.graph.get_point_connections(id)
		var expected := reference.graph.get_point_connections(id)
		actual.sort()
		expected.sort()
		edges_match = edges_match and actual == expected
	check(iterations < 10000 and nav.ids == reference.ids and edges_match,
		"budgeted navigation nodes and edges match complete regional graph")
	camera.free()
	builder.free()
	await physics_frame
	var report_file := FileAccess.open("/tmp/aberration-chunk-performance.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(reports, "\t"))
	print("STREAM REPORTS ", JSON.stringify(reports))
	print("STREAM CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
