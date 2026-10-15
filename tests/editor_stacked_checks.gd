@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var original_data: LevelData = plugin.data
	var original_builder: TerrainBuilder = plugin.builder
	plugin._disable_2_5d_view()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	plugin.get_tree().root.add_child(viewport)
	var map := LevelData.new()
	map.setup_blank(Vector2i(5, 5))
	var cell := Vector2i(2, 2)
	map.set_layer(cell, 0, {"tile_id": "grass"})
	var builder := TerrainBuilder.new()
	builder.level_data = map
	builder.show_grid = false
	viewport.add_child(builder)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 12, 10)
	camera.look_at(Vector3(0, 2, 0))
	plugin.builder = builder
	plugin.data = map
	plugin.tabs.current_tab = 0
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 0
	plugin.height_select.selected = 2
	plugin.tile_turns = 0
	plugin._make_preview()
	select_tile(plugin, "rock")
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var initial := map.clone_data()
	var screen := camera.unproject_position(map.world_center(cell))
	click(plugin, camera, screen)
	suite.check(plugin.height_select.selected == 2 and map.layer_count(cell) == 3
		and map.solid_tile_id(cell, 0) == "grass" and map.solid_tile_id(cell, 2) == "rock",
		"real click preserves chosen layer and automatically fills support")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	plugin.height_select.selected = 0
	plugin._update_preview(cell)
	history.undo()
	suite.check(map.clone_data() == initial, "one undo removes high block and generated support")
	var undo_preview: TerrainBuilder = plugin.preview.get_child(0)
	suite.check(undo_preview.level_data.layer_count(Vector2i.ZERO) == 1,
		"undo invalidates the hovered preview and removes stale upper blocks")
	history.redo()
	plugin.height_select.selected = 1
	select_tile(plugin, "ground_stone")
	var before_middle := map.clone_data()
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	click(plugin, camera, camera.unproject_position(map.world_center(cell)))
	suite.check(map.solid_tile_id(cell, 0) == "grass"
		and map.solid_tile_id(cell, 1) == "ground_stone"
		and map.solid_tile_id(cell, 2) == "rock",
		"real middle-layer click replaces B without modifying A or C")
	history.undo()
	suite.check(map.clone_data() == before_middle, "middle-layer undo restores exact column")
	history.redo()
	plugin.mode_select.selected = 2
	plugin.erase_select.selected = 0
	var before_erase := map.clone_data()
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	plugin._paint(cell)
	plugin._commit_stroke("rejected middle erase")
	suite.check(map.clone_data() == before_erase, "middle erasure changes neither terrain nor dependencies")
	plugin.slice_select.select(2)
	plugin._slice_changed(2)
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var screen_b := camera.unproject_position(map.world_center(cell, 1))
	suite.check(plugin._pick(camera, screen_b) == cell and plugin.picked_layer == 1,
		"editor picks B on the temporary slice cap")
	var before_sample := map.clone_data()
	plugin.height_select.select(0)
	var sample := InputEventMouseButton.new()
	sample.button_index = MOUSE_BUTTON_LEFT
	sample.position = screen_b
	sample.alt_pressed = true # macOS Option is delivered as Alt by Godot.
	sample.pressed = true
	plugin._forward_3d_gui_input(camera, sample)
	sample.pressed = false
	plugin._forward_3d_gui_input(camera, sample)
	suite.check(plugin.height_select.selected == 1 and map.clone_data() == before_sample
		and not plugin.drawing, "Option-click selects the visible layer without painting")
	plugin.slice_select.select(0)
	plugin._slice_changed(0)
	plugin.mode_select.selected = 0
	plugin.height_select.selected = 2
	select_tile(plugin, "decal_corruption")
	plugin.touched.clear()
	plugin._paint_single(cell, 0)
	suite.check(map.overlay_tile_id(cell) == "decal_corruption"
		and map.layer_count(cell) == 3 and map.solid_tile_id(cell) == "rock",
		"overlay brush preserves all solids")
	plugin.mode_select.selected = 2
	plugin.erase_select.selected = 2
	plugin.touched.clear()
	plugin._paint_single(cell, 2)
	suite.check(map.overlay_tile_id(cell).is_empty() and map.layer_count(cell) == 3,
		"erase-overlay tool leaves supporting column intact")
	# A 3x3 dab must reject the whole edit even when the invalid target is last.
	var neighbor := cell + Vector2i.ONE
	map.set_layer(neighbor, 3, {"tile_id": "sand"})
	plugin.brush_select.selected = 1
	plugin.erase_select.selected = 0
	plugin.touched.clear()
	var before_dab := map.clone_data()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	plugin._paint(cell)
	suite.check(map.clone_data() == before_dab, "3x3 top erase rejects an occupied upper layer atomically")
	var large := LevelData.new()
	large.setup_blank(Vector2i(128, 128))
	plugin.data = large
	plugin.mode_select.selected = 0
	plugin.height_select.selected = 3
	select_tile(plugin, "rock")
	var started := Time.get_ticks_usec()
	var target: Array[Vector2i] = [Vector2i(64, 64)]
	for i in 20:
		plugin._prepare_ground(target)
	var average := (Time.get_ticks_usec() - started) / 20
	suite.check(average < 16000 and not large.cell_exists(target[0]),
		"128x128 brush validation stays under 16ms without mutation (%dus)" % average)
	for brush in 2:
		plugin.brush_select.selected = brush
		plugin._update_preview(Vector2i(63, 64))
		started = Time.get_ticks_usec()
		for x in range(64, 72):
			plugin._update_preview(Vector2i(x, 64))
		average = (Time.get_ticks_usec() - started) / 8
		suite.check(average < 100000,
			"layer-3 brush %dx%d preview CPU time under 100ms (%dus)" % [
				1 if brush == 0 else 3, 1 if brush == 0 else 3, average])
		started = Time.get_ticks_usec()
		for i in 100:
			plugin._update_preview(Vector2i(71, 64))
		average = (Time.get_ticks_usec() - started) / 100
		suite.check(average < 1000, "unchanged preview reuses generated terrain (%dus)" % average)
		await plugin.get_tree().process_frame
	plugin.data = original_data
	plugin.builder = original_builder
	plugin.editing_camera = null
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 0
	plugin.erase_select.selected = 0
	plugin.height_select.selected = 0
	plugin._make_preview()
	viewport.free()

func select_tile(plugin: EditorPlugin, id: String) -> void:
	var tiles := TileRegistry.all_tiles()
	for i in tiles.size():
		if tiles[i].tile_id == id:
			plugin.tile_list.select(i)
			return

func click(plugin: EditorPlugin, camera: Camera3D, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	plugin._forward_3d_gui_input(camera, event)
	event.pressed = false
	plugin._forward_3d_gui_input(camera, event)
