@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var right_delete_before: bool = plugin.default_right_delete.button_pressed
	plugin.default_right_delete.set_pressed_no_signal(true)
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
	plugin.active_layer = 0
	plugin.tile_turns = 0
	plugin._make_preview()
	select_tile(plugin, "rock")
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var initial := map.clone_data()
	var screen := camera.unproject_position(map.world_center(cell))
	click(plugin, camera, screen)
	suite.check(plugin.active_layer == 1 and map.layer_count(cell) == 2
		and map.solid_tile_id(cell, 0) == "grass" and map.solid_tile_id(cell, 1) == "rock",
		"real top click places the neighboring block without a height selector")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	plugin._update_preview(cell)
	history.undo()
	suite.check(map.clone_data() == initial, "one undo restores the exact starting map")
	var undo_preview: TerrainBuilder = plugin.preview.get_child(0)
	suite.check(undo_preview.level_data.layer_exists(Vector2i.ZERO, 1)
		and not undo_preview.level_data.layer_exists(Vector2i.ZERO, 0),
		"preview contains only the candidate block and no generated support")
	history.redo()
	select_tile(plugin, "ground_stone")
	var before_side := map.clone_data()
	var front := camera.unproject_position(map.world_layer_center(cell, 1) + Vector3.BACK)
	click(plugin, camera, front)
	var side := cell + Vector2i(0, 1)
	suite.check(map.solid_tile_id(side, 1) == "ground_stone"
		and map.layer_exists(side, 1) and not map.layer_exists(side, 0)
		and map.get_column(cell) == before_side["columns"][map.index(cell)],
		"real side click extends a floating block at the pointed height")
	history.undo()
	suite.check(map.clone_data() == before_side, "side placement undo restores the exact map")
	plugin.erase_select.selected = 0
	var before_erase := map.clone_data()
	click(plugin, camera, camera.unproject_position(map.world_layer_center(cell, 0) + Vector3.BACK),
		MOUSE_BUTTON_RIGHT)
	suite.check(not map.layer_exists(cell, 0) and map.layer_exists(cell, 1),
		"right click erases the pointed lower block and leaves upper blocks suspended")
	history.undo()
	suite.check(map.clone_data() == before_erase, "right erase undo restores exact layers")
	map.set_layer(cell, 3, {"tile_id": "sand"})
	builder.rebuild_cells([cell])
	plugin.slice_select.select(3)
	plugin._slice_changed(3)
	var screen_b := camera.unproject_position(map.world_center(cell, 1))
	suite.check(plugin._pick(camera, screen_b) == cell and plugin.picked_layer == 1,
		"slice through air picks the real surface below it")
	suite.check(plugin.active_layer == 0, "display filtering never changes the placement target")
	plugin.slice_select.select(0)
	plugin._slice_changed(0)
	plugin.mode_select.selected = 0
	plugin.active_layer = 1
	select_tile(plugin, "decal_corruption")
	plugin.touched.clear()
	plugin._paint_single(cell, 0)
	suite.check(map.overlay_tile_id(cell, 1) == "decal_corruption"
		and map.layer_count(cell) == 4 and map.solid_tile_id(cell, 1) == "rock",
		"overlay brush targets an exposed lower surface and preserves all solids")
	plugin.erase_select.selected = 2
	plugin.touched.clear()
	plugin._paint_single(cell, 2)
	suite.check(map.overlay_tile_id(cell, 1).is_empty() and map.layer_count(cell) == 4,
		"erase-overlay tool leaves supporting column intact")
	# A right press is a single deletion, even with the large placement brush.
	var neighbor := cell + Vector2i.ONE
	map.set_layer(neighbor, 1, {"tile_id": "sand"})
	map.set_layer(neighbor, 0, {"tile_id": "grass"})
	builder.rebuild_cells([neighbor])
	plugin.brush_select.selected = 1
	plugin.erase_select.selected = 0
	var before_click := map.clone_data()
	var expected := map.fork_for_edit()
	expected.remove_layer(neighbor, 1)
	var dab_point := camera.unproject_position(map.world_center(neighbor, 1))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = dab_point
	press.pressed = true
	plugin._forward_3d_gui_input(camera, press)
	var after_click := map.clone_data()
	suite.check(after_click == expected.clone_data() and not plugin.drawing,
		"right press deletes exactly one block even with a 3x3 placement brush")
	var motion := InputEventMouseMotion.new()
	motion.position = dab_point
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	for i in 3:
		plugin._forward_3d_gui_input(camera, motion)
	motion.position = camera.unproject_position(map.world_center(cell, 3))
	plugin._forward_3d_gui_input(camera, motion)
	plugin._forward_3d_gui_input(camera, press)
	suite.check(map.clone_data() == after_click,
		"holding, dragging and a repeated right press never delete another block")
	press.pressed = false
	plugin._input(press)
	history.undo()
	suite.check(map.clone_data() == before_click,
		"single deletion is one undo action after release outside the viewport")
	history.redo()
	suite.check(map.clone_data() == after_click, "single deletion redo restores exactly one change")
	click(plugin, camera, camera.unproject_position(map.world_center(neighbor, 0)), MOUSE_BUTTON_RIGHT)
	suite.check(not map.layer_exists(neighbor, 0) and map.layer_exists(cell, 1),
		"a fresh right click can delete the next block without touching its neighbors")
	plugin.brush_select.selected = 0
	select_tile(plugin, "rock")
	var stack_cell := Vector2i(4, 4)
	var base_point := map.world_center(stack_cell, 0) - Vector3.UP * LevelData.ELEVATION_STEP
	click(plugin, camera, camera.unproject_position(base_point), MOUSE_BUTTON_LEFT, true)
	suite.check(map.layer_exists(stack_cell, 0) and map.layer_count(stack_cell) == 1,
		"Shift click uses the ground plane instead of creating a block in midair")
	click(plugin, camera, camera.unproject_position(map.world_center(stack_cell, 0)))
	var stack_top := camera.unproject_position(map.world_center(stack_cell, 1))
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = stack_top
	press.pressed = true
	plugin._forward_3d_gui_input(camera, press)
	motion.position = stack_top
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	for i in 3:
		plugin._forward_3d_gui_input(camera, motion)
	# Releasing outside the 3D viewport must still commit exactly one stroke.
	press.pressed = false
	plugin._input(press)
	suite.check(map.layer_exists(stack_cell, 2) and not map.layer_exists(stack_cell, 3)
		and not plugin.drawing, "left drag locks its starting plane and outside release commits")
	history.undo()
	suite.check(map.layer_exists(stack_cell, 1) and not map.layer_exists(stack_cell, 2),
		"one undo restores a plane-locked stroke after outside release")
	click(plugin, camera, camera.unproject_position(
		map.world_layer_center(stack_cell, 0) + Vector3.BACK), MOUSE_BUTTON_RIGHT)
	suite.check(not map.layer_exists(stack_cell, 0) and map.layer_exists(stack_cell, 1),
		"building upward then deleting the base leaves the upper block suspended")
	await check_delete_switch(plugin, suite, camera, map, builder)
	plugin.stroke_erase = false
	plugin.hover_normal = Vector3i.UP
	var large := LevelData.new()
	large.setup_blank(Vector2i(128, 128))
	plugin.data = large
	plugin.mode_select.selected = 0
	plugin.active_layer = 3
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
	# The empty-map benchmark cannot catch a full terrain rebuild on expansion.
	var populated := LevelData.new()
	populated.setup_blank(Vector2i(64, 64))
	for y in 64:
		for x in 64:
			populated.set_layer(Vector2i(x, y), 0, {"tile_id": "painted_grass"})
	plugin.data = populated
	builder.level_data = populated
	builder.rebuild()
	plugin.active_layer = 0
	plugin.brush_select.selected = 1
	select_tile(plugin, "painted_grass")
	plugin._make_preview()
	await plugin.get_tree().process_frame
	var before_expansion := populated.clone_data()
	var generated := builder.generated
	var remote: Array = builder._chunk_nodes[Vector2i(3, 3)].duplicate()
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	var edge := Vector2i(-1, 20)
	started = Time.get_ticks_usec()
	plugin._ensure_ground_bounds(edge)
	plugin._paint(edge)
	plugin._commit_stroke("Populated map edge paint")
	var elapsed := Time.get_ticks_usec() - started
	var retained := generated == builder.generated
	for node in remote:
		retained = retained and is_instance_valid(node) and node.is_inside_tree()
	suite.check(retained and populated.cell_exists(Vector2i(-2, 20)),
		"populated 64x64 edge brush preserves distant terrain meshes and collisions")
	suite.check(elapsed < 250000,
		"populated 64x64 expansion stroke stays under 250ms (%dus)" % elapsed)
	var after_expansion := populated.clone_data()
	var expansion_history := plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(populated))
	expansion_history.undo()
	suite.check(populated.clone_data() == before_expansion,
		"populated expansion undo restores complete terrain and original bounds")
	expansion_history.redo()
	suite.check(populated.clone_data() == after_expansion,
		"populated expansion redo restores complete terrain and expanded bounds")
	# Exercise the full-map dependency checks that an empty-object fixture misses.
	for i in 32:
		var object_cell := Vector2i(4 + (i % 8) * 2, 4 + (i / 8) * 2)
		var asset := "demo_tree" if i % 2 == 0 else "demo_rock"
		populated.objects.append(ObjectRules.anchor_record(populated, {
			"id": "preview_perf_%d" % i,
			"definition": "res://assets/generated/%s/definition.tres" % asset,
			"position": populated.world_center(object_cell), "scale": 1.0, "yaw": 0.0}))
	builder.rebuild()
	var fixed_bounds := populated.map_bounds()
	plugin._make_preview()
	plugin._update_preview(Vector2i(29, 30))
	started = Time.get_ticks_usec()
	for i in 8:
		plugin._update_preview(Vector2i(30 + i, 30))
	average = (Time.get_ticks_usec() - started) / 8
	suite.check(average < 16000 and populated.map_bounds() == fixed_bounds,
		"interior brush preview with 32 objects stays under 16ms without expanding (%dus)" % average)
	suite.check(ObjectRules.validate_all(populated).is_empty(),
		"interior brush preview retains valid object support and collision checks")
	plugin.data = original_data
	plugin.builder = original_builder
	plugin.editing_camera = null
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 0
	plugin.erase_select.selected = 0
	plugin.active_layer = 0
	plugin._make_preview()
	viewport.free()
	plugin.default_right_delete.set_pressed_no_signal(right_delete_before)

func check_delete_switch(plugin: EditorPlugin, suite: RefCounted, camera: Camera3D,
		map: LevelData, builder: TerrainBuilder) -> void:
	var cell := Vector2i(0, 0)
	map.set_layer(cell, 0, {"tile_id": "grass"})
	builder.rebuild_cells([cell])
	var point := camera.unproject_position(map.world_center(cell, 0))
	plugin.default_right_delete.set_pressed_no_signal(false)
	var before := map.clone_data()
	click(plugin, camera, point, MOUSE_BUTTON_RIGHT)
	suite.check(map.clone_data() == before, "disabled switch prevents ordinary right-click terrain deletion")
	click(plugin, camera, point, MOUSE_BUTTON_RIGHT, false, true)
	suite.check(not map.layer_exists(cell, 0), "disabled switch deletes terrain with Alt-right click")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	history.undo()
	suite.check(map.clone_data() == before, "Alt-right terrain deletion supports exact undo")
	map.objects.append(ObjectRules.anchor_record(map, {"id": "right_click_rock",
		"definition": "res://assets/generated/painted_rock/definition.tres",
		"position": map.world_center(cell, 0), "scale": 1.0, "yaw": 0.0}))
	builder.refresh_objects()
	point = camera.unproject_position(map.world_center(cell, 0) + Vector3.UP)
	var generated := builder.generated
	var terrain_nodes: Array = builder._chunk_nodes[Vector2i.ZERO].duplicate()
	before = map.clone_data()
	click(plugin, camera, point, MOUSE_BUTTON_RIGHT, false, true)
	suite.check(ObjectRules.find_record(map, "right_click_rock").is_empty()
		and map.layer_exists(cell, 0) and builder.generated == generated,
		"Alt-right deletes a pointed object while retaining its terrain")
	history.undo()
	var retained := true
	for node in terrain_nodes:
		retained = retained and is_instance_valid(node)
	suite.check(map.clone_data() == before and retained, "object undo preserves existing terrain nodes")
	plugin.tabs.current_tab = 1
	plugin.default_right_delete.set_pressed_no_signal(true)
	click(plugin, camera, point, MOUSE_BUTTON_RIGHT)
	suite.check(ObjectRules.find_record(map, "right_click_rock").is_empty()
		and map.layer_exists(cell, 0), "object page also supports ordinary right-click deletion")
	history.undo()
	plugin.tabs.current_tab = 0

func select_tile(plugin: EditorPlugin, id: String) -> void:
	var tiles := TileRegistry.all_tiles()
	for i in tiles.size():
		if tiles[i].tile_id == id:
			plugin.tile_list.select(i)
			return

func click(plugin: EditorPlugin, camera: Camera3D, point: Vector2,
		button := MOUSE_BUTTON_LEFT, shift := false, alt := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.position = point
	event.pressed = true
	plugin._forward_3d_gui_input(camera, event)
	event.pressed = false
	plugin._forward_3d_gui_input(camera, event)
