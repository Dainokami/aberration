@tool
extends RefCounted

var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	print("ENCOUNTER EDITOR CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	if "--encounter-interactive" in OS.get_cmdline_user_args():
		var scene := EditorInterface.get_edited_scene_root()
		if scene == null:
			await tree.create_timer(1.0).timeout
			scene = EditorInterface.get_edited_scene_root()
		var demo := scene.get_node("TerrainBuilder") as TerrainBuilder
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(demo)
		plugin._edit(demo)
		plugin.editor_dock.make_visible()
		plugin.tabs.current_tab = plugin.tabs.get_tab_count()-1
		plugin.encounter_tools.overlay_toggle.button_pressed = true
		plugin._enable_2_5d_view()
		print("ENCOUNTER INTERACTIVE READY ",plugin.data.resource_path)
		for i in 10:
			await tree.process_frame
		var folder := "/Users/bytedance/Desktop/godot/怪物刷新_验收截图"
		DirAccess.make_dir_recursive_absolute(folder)
		tree.root.get_texture().get_image().save_png(folder+"/04_编辑器怪物页.png")
		return
	plugin._disable_2_5d_view()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	tree.root.add_child(viewport)
	var map := LevelData.new()
	map.setup_blank(Vector2i(12, 12))
	for i in map.columns.size():
		map.columns[i] = {"layers":[{"tile_id":"painted_grass"}]}
	map.spawn_cell = Vector2i(6, 6)
	map.set_layer(Vector2i(6, 6), 2, {"tile_id":"painted_grass"})
	var builder := TerrainBuilder.new()
	builder.level_data = map
	viewport.add_child(builder)
	plugin._edit(builder)
	plugin.tabs.current_tab = plugin.tabs.get_tab_count() - 1
	var tools = plugin.encounter_tools
	check(tools.active() and not map.encounter, "new final tab and old map default off")
	check(not tools.page.visible and tools.point_editor.visible, "planner main page focuses on points with advanced settings collapsed")
	tools.controls.enabled.button_pressed = true
	await tree.process_frame
	await tree.process_frame
	check(map.encounter != null and map.encounter.enabled, "real enable control edits map config")
	var history := plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	history.undo()
	await tree.process_frame
	check(map.encounter == null, "native undo returns untouched optional config")
	history.redo()
	await tree.process_frame
	tools.pool_rows.find_child("demon_dog_enabled", true, false).button_pressed = false
	await tree.process_frame
	check(not map.encounter.monster_pool[2].enabled,
		"pool signal safely updates without freeing active callback")
	history.undo()
	await tree.process_frame
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 24, 18)
	camera.look_at(Vector3(0, 2, 0))
	await tree.physics_frame
	await tree.physics_frame
	var points = tools.point_editor
	points.find_child("NewSpawnPoint", true, false).pressed.emit()
	check(map.monster_spawn_points.is_empty() and not points.draft.is_empty(), "new point remains draft until painted")
	var first := Vector2i(2, 2)
	var adjacent := Vector2i(3, 2)
	var press_point := InputEventMouseButton.new()
	press_point.button_index = MOUSE_BUTTON_LEFT
	press_point.pressed = true
	press_point.position = camera.unproject_position(map.world_center(first, 0))
	plugin._forward_3d_gui_input(camera, press_point)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(map.world_center(adjacent, 0))
	plugin._forward_3d_gui_input(camera, motion)
	press_point.pressed = false
	plugin._input(press_point)
	check(map.monster_spawn_points.size() == 1 and map.monster_spawn_points[0].cells.size() == 2,
		"real projected press drag outside release paints adjacent group")
	check(not points.drawing and tools.overlay.get_child_count() > 0, "stroke commits and points visibly rendered")
	var point_id := str(map.monster_spawn_points[0].id)
	history.undo()
	check(map.monster_spawn_points.is_empty(), "point native undo")
	history.redo()
	check(map.monster_spawn_points.size() == 1 and str(map.monster_spawn_points[0].id) == point_id, "point native redo keeps stable ID")
	points.mode.select(1)
	click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(8, 2), 0)))
	check(map.monster_spawn_points[0].cells.size() == 2, "detached mouse click rejected")
	points.mode.select(2)
	click(plugin, camera, camera.unproject_position(map.world_center(adjacent, 0)))
	check(map.monster_spawn_points[0].cells.size() == 1, "point erase mode uses actual mouse input")
	history.undo()
	points.mode.select(0)
	click(plugin, camera, camera.unproject_position(map.world_center(first, 0)))
	check(points.selected_id == point_id, "click existing range selects point")
	points.limit.value = 3
	check(map.monster_spawn_points[0].max_alive == 3, "alive control persists")
	history.undo()
	points.radius_control.value = 24
	check(map.monster_spawn_points[0].activation_radius == 24, "shared radius control persists in map")
	history.undo()
	check(map.monster_spawn_points[0].get("activation_radius", 0) == 0, "radius undo restores automatic mode")
	check(tools.overlay.find_child("SpawnPointActivationRing", true, false) != null,
		"selected point displays actual activation and chase circle")
	points.delete_point()
	check(map.monster_spawn_points.is_empty(), "delete point control")
	history.undo()
	check(map.monster_spawn_points.size() == 1, "delete undo")
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.erase_select.select(0)
	var erase_targets: Array[Vector3i] = [Vector3i(first.x, 0, first.y)]
	var changes: Array[Dictionary] = plugin._erase_blocks(erase_targets)
	plugin._record_stroke_changes(changes)
	plugin._commit_stroke("test point terrain erase")
	check(map.monster_spawn_points[0].cells == [Vector3i(adjacent.x, 0, adjacent.y)], "terrain erasure prunes exact point host")
	history.undo()
	check(map.monster_spawn_points[0].cells.size() == 2 and map.layer_exists(first, 0), "terrain undo restores point and support")
	map.set_layer(Vector2i(9, 9), 1, {"tile_id": "water"})
	points.new_point()
	click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(9, 9), 1)))
	check(map.monster_spawn_points.size() == 2 and map.monster_spawn_points[1].cells == [Vector3i(9, 1, 9)],
		"logical mouse picking targets water surface without physical water collider")
	history.undo()
	points.new_point()
	click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(6, 6), 2)))
	check(map.monster_spawn_points.size() == 2 and map.monster_spawn_points[1].cells == [Vector3i(6, 2, 6)],
		"point mouse picking retains upper support layer")
	history.undo()
	tools.paint_toggle.button_pressed = true
	tools.region_mode.selected = 1
	var cell := Vector2i(5, 5)
	click(plugin, camera, camera.unproject_position(map.world_center(cell, 0)))
	check(EncounterRegions.zone(map, cell, 0) == 1 and plugin.dirty,
		"real projected left click paints actual exposed surface")
	history.undo()
	check(EncounterRegions.zone(map, cell, 0) == 0, "region native undo")
	history.redo()
	check(EncounterRegions.zone(map, cell, 0) == 1, "region native redo")
	tools.region_mode.selected = 2
	click(plugin, camera, camera.unproject_position(map.world_center(cell, 0)))
	check(EncounterRegions.zone(map, cell, 0) == 1 and EncounterRegions.forbidden(map, cell, 0),
		"forbidden independent from static zone")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = camera.unproject_position(map.world_center(Vector2i(3,3),0))
	plugin._forward_3d_gui_input(camera,press)
	press.pressed = false
	plugin._input(press)
	check(not tools.drawing and EncounterRegions.forbidden(map,Vector2i(3,3),0),
		"release outside viewport commits one region stroke")
	history.undo()
	check(not EncounterRegions.forbidden(map,Vector2i(3,3),0),
		"outside-release stroke supports native undo")
	tools.region_mode.selected = 1
	click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(6, 6), 2)))
	check(EncounterRegions.zone(map, Vector2i(6, 6), 2) == 1 \
		and EncounterRegions.zone(map, Vector2i(6, 6), 0) == 0,
		"upper surface painting preserves lower tunnel region")
	tools.overlay_toggle.button_pressed = true
	check(tools.overlay != null and tools.overlay.get_child_count() > 0,
		"region overlay has real multimeshes")
	var overlay: Node3D = tools.overlay
	check(overlay.owner == null and overlay.find_children("*", "CollisionObject3D").is_empty(),
		"overlay is transient and does not add collisions")
	plugin._slice_changed(1)
	check(tools.overlay != overlay, "slice refreshes overlay")
	tools._preview_ring()
	check(tools.overlay != null, "ring preview creates legal-point overlay")
	var path := "/tmp/aberration-encounter-editor-roundtrip.tres"
	check(ResourceSaver.save(map, path) == OK, "actual editor map saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.encounter.enabled and loaded.encounter_regions == map.encounter_regions \
		and loaded.monster_spawn_points == map.monster_spawn_points,
		"reopen preserves settings and layered paint")
	var other := LevelData.new()
	other.setup_blank()
	plugin.data = other
	history.undo()
	check(other.encounter == null and other.encounter_regions.is_empty(),
		"old history cannot write another map")
	tools.reset_overlay()
	plugin.builder = null
	plugin.data = null
	viewport.queue_free()
	await tree.process_frame
	print("ENCOUNTER EDITOR CHECKS ", checks, " FAILURES ", failures)
	tree.quit(0 if failures.is_empty() else 1)

func click(plugin: EditorPlugin, camera: Camera3D, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	plugin._forward_3d_gui_input(camera, event)
	event.pressed = false
	plugin._forward_3d_gui_input(camera, event)
