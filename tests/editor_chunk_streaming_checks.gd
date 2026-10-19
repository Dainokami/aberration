@tool
extends RefCounted

var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	print("EDITOR STREAM ", value, " ", label)
	if not value:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	tree.root.add_child(viewport)
	var map := LevelData.new()
	map.setup_blank(Vector2i(200, 200))
	for i in map.columns.size():
		map.columns[i] = {"layers": [{"tile_id": "grass", "rotation": 0}]}
	map.spawn_cell = Vector2i(100, 100)
	map.spawn_layer = 0
	var builder := TerrainBuilder.new()
	builder.level_data = map
	builder.show_grid = true
	viewport.add_child(builder)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	var focus := map.world_center(map.spawn_cell)
	camera.position = focus + Vector3(0, 40, 20)
	camera.look_at(focus)
	plugin._disable_2_5d_view()
	plugin.builder = builder
	plugin.data = map
	plugin.editing_camera = camera
	plugin.tabs.current_tab = 0
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 0
	plugin.tile_turns = 0
	plugin._make_preview()
	builder.follow_stream_camera(camera)
	builder.chunk_stream.select(builder, true)
	await settle(tree, builder)
	check(builder.is_streaming() and builder._chunk_nodes.size() < 80,
		"large editor map loads camera working set")
	var cell := Vector2i(100, 100)
	var before := map.column_snapshot(cell)
	var tile_index := -1
	var tiles := TileRegistry.all_tiles()
	for i in tiles.size():
		if tiles[i].tile_id == "rock":
			tile_index = i
			break
	plugin.tile_list.select(tile_index)
	var screen := camera.unproject_position(map.world_center(cell))
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = screen
		plugin._forward_3d_gui_input(camera, event)
	check(map.is_solid_layer(cell, 1), "actual editor click adds block on streamed ground")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	history.undo()
	check(map.column_snapshot(cell) == before, "streamed painting undo restores exact column")
	history.redo()
	check(map.is_solid_layer(cell, 1), "streamed painting redo restores block")
	map.details.append({"id": "editor_detail", "set": "res://data/details/painted_flat.tres",
		"variant": "detail_02", "position": map.world_center(cell, 1),
		"anchor_cell": cell, "anchor_layer": 1, "scale": 1.0, "yaw": 0.0})
	builder.rebuild_details()
	check(not builder.detail_renderer.groups.is_empty(),
		"standalone detail brush refresh updates streamed chunk index")
	map.details.clear()
	builder.rebuild_details()
	check(builder.detail_renderer.groups.is_empty(),
		"standalone detail erase clears streamed batch")
	focus = map.world_center(Vector2i(30, 30))
	camera.position = focus + Vector3(0, 40, 20)
	camera.look_at(focus)
	builder.chunk_stream.select(builder, true)
	await settle(tree, builder)
	check(not builder.stream_cell_loaded(cell) and builder.stream_cell_loaded(Vector2i(30, 30)),
		"editor camera travel unloads old area and loads new area")
	history.undo()
	check(map.column_snapshot(cell) == before and not builder.stream_cell_loaded(cell),
		"undo remote edit updates data without loading distant area")
	camera.size = 60
	builder.chunk_stream.select(builder, true)
	var zoom_count := builder.chunk_stream.wanted.size()
	await settle(tree, builder)
	check(zoom_count > 20 and builder._chunk_nodes.size() < 120,
		"camera zoom expands working set without whole map")
	builder.set_slice_layer(0)
	await tree.physics_frame
	check(ResourceSaver.save(map, "/tmp/stream-editor-saved.tres") == OK, "save streamed map")
	var loaded := ResourceLoader.load("/tmp/stream-editor-saved.tres", "",
		ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.columns == map.columns and loaded.map_size == Vector2i(200, 200),
		"save reload includes unloaded map content")
	plugin._disable_2_5d_view()
	plugin.builder = null
	plugin.data = null
	plugin.editing_camera = null
	viewport.queue_free()
	await tree.process_frame
	print("EDITOR STREAM FAILURES ", failures)
	tree.quit(0 if failures.is_empty() else 1)

func settle(tree: SceneTree, builder: TerrainBuilder) -> void:
	for i in 1000:
		await tree.process_frame
		if builder.chunk_stream.pending.is_empty() and not is_instance_valid(builder.chunk_stream.job_root):
			for frame in 50:
				await tree.process_frame
			return
	check(false, "stream queue timeout")
