@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var original: LevelData = plugin.data
	var map := LevelData.new()
	map.setup_blank()
	plugin.data = map
	plugin.builder.level_data = map
	plugin.builder.rebuild()
	var ids := ["ground_forest", "ground_stone", "sand", "rock"]
	var tiles := TileRegistry.all_tiles()
	for i in ids.size():
		for j in tiles.size():
			if tiles[j].tile_id == ids[i]:
				plugin.tile_list.select(j)
		plugin.touched.clear()
		plugin._paint_single(Vector2i(i + 4, 4), 0)
	plugin.builder.rebuild()
	for i in ids.size():
		var cell := Vector2i(i + 4, 4)
		var top := _top_visual(plugin.builder, cell)
		var mat := top.material_override as ShaderMaterial
		suite.check(map.tile_id(cell) == ids[i] and mat != null and
			top.get_meta("terrain_tiles", PackedStringArray()).has(ids[i]) and
			mat.get_shader_parameter("terrain_art") is Texture2DArray,
			"painted mesh uses dynamic texture array page " + ids[i])

	var tools = plugin.world_tools
	tools.refresh_library()
	for i in 2:
		var id: String = ["tree_dead", "tree_olive"][i]
		var cell := Vector2i(4 + i * 2, 4)
		var path := "res://assets/generated/%s/definition.tres" % id
		tools.library.select(tools.paths.find(path))
		tools.scale_input.value = 1
		tools.yaw_input.value = 0
		var record: Dictionary = tools._candidate(map.world_center(cell))
		tools.place_object(record)
		var found := false
		for node in plugin.builder.generated.get_children():
			if node.get_meta("object_id", "") == record["id"]:
				found = true
		suite.check(map.objects.size() == i + 1 and found,
			"place tree updates data AND generated scene " + id)
	var before := map.clone_data()
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	plugin.touched.clear()
	plugin._paint_single(Vector2i(4, 4), 2)
	plugin._commit_external(before, map.clone_data(), "Regression erase with tree")
	suite.check(not map.cell_exists(Vector2i(4, 4)) and map.objects.size() == 1,
		"erase removes supporting cell and its tree")
	suite.check(not plugin.builder.generated.has_node("Top_4_4"),
		"erased cell mesh and collision removed")
	history.undo()
	suite.check(map.clone_data() == before and plugin.builder.generated.has_node("Top_4_4"),
		"real undo restores cell and tree")
	history.redo()
	suite.check(not map.cell_exists(Vector2i(4, 4)) and map.objects.size() == 1,
		"real redo erases cell and tree")
	var other := LevelData.new()
	other.setup_blank()
	plugin.data = other
	plugin.builder.level_data = other
	history.undo()
	suite.check(other.objects.is_empty() and map.clone_data() == before,
		"undo bound to original map after switching")
	plugin.data = map
	plugin.builder.level_data = map
	plugin.mode_select.selected = 0
	plugin.active_layer = 2
	plugin.tile_turns = 1
	var before_replace := map.clone_data()
	plugin.touched.clear()
	plugin._paint_single(Vector2i(4, 4), 0)
	plugin._commit_external(before_replace, map.clone_data(), "Replace height and rotation")
	suite.check(map.elevation(Vector2i(4, 4)) == 2 and map.get_cell(Vector2i(4, 4))["rotation"] == 1,
		"floating placement stores its own height and rotation")
	suite.check(is_equal_approx(map.objects[0]["position"].y, 2.0)
		and not map.layer_exists(Vector2i(4, 4), 1),
		"floating placement retains lower tree height and an empty gap")
	var rotated_top := _top_visual(plugin.builder, Vector2i(4, 4), 2)
	suite.check((rotated_top.material_override as ShaderMaterial).get_shader_parameter("art_turns") == 1,
		"rotated ground material uses stored rotation")
	plugin._update_preview(Vector2i(4, 4))
	var display := plugin.preview.get_child(0) as TerrainBuilder
	var preview_top := _top_visual(display, Vector2i.ZERO)
	suite.check(not display.build_collision and preview_top.mesh.get_aabb().position.y > 5.9 and
		(preview_top.material_override as ShaderMaterial).get_shader_parameter("art_turns") == 1 and
		(preview_top.material_override as ShaderMaterial).get_shader_parameter("upper_art") != null,
		"brush previews textured mesh at requested height and rotation without collision")
	history.undo()
	suite.check(map.clone_data() == before_replace, "undo restores replaced height rotation and tree")
	# Same-height different terrain creates one deterministic transition; high
	# differences remain cliffs and never receive a top-surface mask.
	var transition_map := LevelData.new()
	transition_map.setup_blank(Vector2i(4, 3))
	transition_map.set_cell(Vector2i(1, 1), {"exists": true, "height": 0,
		"terrain": 0, "tile_id": "ground_forest"})
	transition_map.set_cell(Vector2i(2, 1), {"exists": true, "height": 0,
		"terrain": 0, "tile_id": "ground_stone"})
	plugin.builder.level_data = transition_map
	plugin.builder.rebuild()
	var transition_anchor: Node = plugin.builder.generated.get_node("Top_2_1")
	var transition_top := _top_visual(plugin.builder, Vector2i(2, 1))
	suite.check(transition_anchor.get_meta(
		"blend_terrains", PackedStringArray()).has("ground_forest") and
		transition_anchor.get_meta(
			"blend_terrains", PackedStringArray()).has("ground_stone") and
		transition_top.get_meta("multi_blend", false),
		"same-height custom terrains enter the dynamic blend layer")
	var transition_material := transition_top.material_override as ShaderMaterial
	suite.check(transition_material.get_shader_parameter("blend_indices") is Texture2D and
		transition_material.get_shader_parameter("blend_weights") is Texture2D,
		"custom transition uses topology-driven index and weight maps")
	transition_map.set_layer(Vector2i(2, 1), 1, {"tile_id": "ground_stone"})
	plugin.builder.rebuild()
	transition_anchor = plugin.builder.generated.get_node("Top_2_1")
	suite.check(not transition_anchor.has_meta("transition_lower") and
		not plugin.builder.generated.find_children("Side", "MeshInstance3D", false, false).is_empty(),
		"height difference remains cliff without planar mask")
	plugin.builder.level_data = map
	plugin.builder.rebuild()
	# Exercise the same save writer and request reader used by the play button.
	var previous_path: String = plugin.current_path
	var unique := ObjectRules.new_id()
	var saved_path := "res://data/levels/test_play_%s.tres" % unique
	var request_path := "user://test_play_%s.cfg" % unique
	map.spawn_cell = Vector2i(5, 4)
	map.spawn_layer = map.top_layer(map.spawn_cell)
	plugin.current_path = saved_path
	suite.check(plugin._save_map(), "save current map succeeds")
	suite.check(plugin._write_playtest_request(request_path), "current map request writes")
	var request := ConfigFile.new()
	request.load(request_path)
	var runtime = load("res://scripts/runtime/level_playtest.gd")
	var resolved: String = runtime.resolve_level_path(request, PackedStringArray())
	var played := ResourceLoader.load(resolved, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	suite.check(resolved == saved_path and played.clone_data() == map.clone_data(),
		"runtime request resolves EXACT saved current map")
	request.set_value("playtest", "level", "res://data/levels/acceptance_map.tres")
	suite.check(runtime.resolve_level_path(request, PackedStringArray()) == saved_path,
		"new request key takes priority over stale legacy map")
	suite.check(not plugin._is_map_file("res://scenes/terrain_editor_test.tscn::Resource_test"),
		"embedded scene map requires save-as")
	plugin.play_after_save = true
	plugin.file_dialog.canceled.emit()
	suite.check(not plugin.play_after_save, "cancel save cancels pending play")
	plugin.current_path = "res://missing_directory_for_save_test/map.tres"
	plugin.dirty = true
	suite.check(not plugin._save_map() and plugin.dirty, "save failure prevents play and retains dirty")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	map.set_cell(Vector2i(10, 10), {"exists": true, "height": 0,
		"terrain": 0, "tile_id": "grass"})
	map.set_cell(Vector2i(11, 10), {"exists": true, "height": 0,
		"terrain": 1, "tile_id": "rock"})
	plugin.builder.rebuild()
	plugin.tile_list.select(0)
	plugin._on_tile_selected(0)
	plugin.tint_picker.color = Color("#78a8c0")
	plugin.tint_strength.value = 0.6
	plugin._apply_current_tint()
	var tinted_top := _top_visual(plugin.builder, Vector2i(10, 10))
	var tint_material := tinted_top.material_override as ShaderMaterial
	var terrain_ids: PackedStringArray = tinted_top.get_meta("terrain_tiles")
	var tint_lookup := (
		tint_material.get_shader_parameter("terrain_tints") as Texture2D).get_image()
	var tint_parameter := tint_lookup.get_pixel(terrain_ids.find("grass"), 0)
	var expected_tint: Color = plugin.data.terrain_tint("grass")
	suite.check(plugin.data.terrain_tint("grass").a > 0.59
		and absf(tint_parameter.r - expected_tint.r) < 0.015
		and absf(tint_parameter.g - expected_tint.g) < 0.015
		and absf(tint_parameter.b - expected_tint.b) < 0.015
		and absf(tint_parameter.a - expected_tint.a) < 0.015,
		"one-click terrain tint updates data and rendered material")
	plugin._clear_current_tint()
	suite.check(plugin.data.terrain_tint("grass").a == 0.0,
		"restore original color removes map override")
	var performance_map := LevelData.new()
	performance_map.setup_blank()
	var filled_cells := {}
	for y in performance_map.map_size.y:
		for x in performance_map.map_size.x:
			filled_cells[Vector2i(x, y)] = {
				"exists": true,
				"height": 0,
				"terrain": 0,
				"tile_id": "grass",
				"rotation": 0,
			}
	filled_cells[Vector2i(1, 1)]["tile_id"] = "rock"
	filled_cells[Vector2i(1, 1)]["terrain"] = 1
	performance_map.set_cells(filled_cells)
	plugin.data = performance_map
	plugin.builder.level_data = performance_map
	plugin.builder.rebuild()
	var forest_index := -1
	for index in TileRegistry.all_tiles().size():
		if TileRegistry.all_tiles()[index].tile_id == "ground_forest":
			forest_index = index
	plugin.tile_list.select(forest_index)
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 1
	plugin.active_layer = 1
	plugin.tile_turns = 0
	var center := Vector2i(8, 8)
	performance_map.stairs.append({"cell": center, "direction": 1})
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	plugin._paint(center)
	var rejected_atomically := true
	for y in range(7, 10):
		for x in range(7, 10):
			rejected_atomically = rejected_atomically \
				and performance_map.tile_id(Vector2i(x, y)) == "grass"
	suite.check(rejected_atomically,
		"3x3 brush rejects the whole dab when one cell is invalid")
	performance_map.stairs.clear()
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	var generated_before: Node3D = plugin.builder.generated
	var paint_started := Time.get_ticks_usec()
	plugin._paint(center)
	var paint_usec := Time.get_ticks_usec() - paint_started
	plugin._commit_stroke("Regression atomic 3x3 paint")
	var painted_atomically := true
	for y in range(7, 10):
		for x in range(7, 10):
			painted_atomically = painted_atomically \
				and performance_map.tile_id(Vector2i(x, y)) == "ground_forest"
	suite.check(painted_atomically,
		"3x3 brush commits all nine cells together")
	suite.check(plugin.builder.generated == generated_before,
		"plane placement retains the generated root and rebuilds affected chunks")
	suite.check(paint_usec < 250000,
		"3x3 dirty blend refresh stays below 250ms (%dus)" % paint_usec)
	var performance_history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(performance_map))
	performance_history.undo()
	var undo_restored_all := true
	for y in range(7, 10):
		for x in range(7, 10):
			undo_restored_all = undo_restored_all \
				and performance_map.tile_id(Vector2i(x, y)) == "grass"
	suite.check(undo_restored_all,
		"one undo restores the entire 3x3 stroke")
	performance_history.redo()
	suite.check(performance_map.tile_id(center) == "ground_forest",
		"one redo reapplies the entire 3x3 stroke")
	var expansion_map := LevelData.new()
	expansion_map.setup_blank(Vector2i(4, 4))
	var expansion_cells := {}
	for y in expansion_map.map_size.y:
		for x in expansion_map.map_size.x:
			expansion_cells[Vector2i(x, y)] = {
				"exists": true, "height": 0, "terrain": 0,
				"tile_id": "grass", "rotation": 0,
			}
	expansion_cells[Vector2i(3, 2)]["height"] = 1
	expansion_map.set_cells(expansion_cells)
	expansion_map.spawn_cell = Vector2i(1, 1)
	expansion_map.stairs.append({"cell": Vector2i(2, 2), "direction": 1})
	var stable_world := expansion_map.world_center(Vector2i(1, 1))
	plugin.data = expansion_map
	plugin.builder.level_data = expansion_map
	plugin.builder.rebuild()
	plugin.active_layer = 0
	plugin.brush_select.selected = 1
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	suite.check(plugin._ensure_ground_bounds(Vector2i(3, 2)),
		"invalid edge dab can provision temporary bounds")
	plugin._paint(Vector2i(3, 2))
	suite.check(expansion_map.map_origin == Vector2i.ZERO
		and expansion_map.map_size == Vector2i(4, 4),
		"rejected edge dab rolls back temporary expansion")
	plugin._begin_stroke()
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	suite.check(plugin._ensure_ground_bounds(Vector2i(-1, 1)),
		"3x3 brush expands map bounds before painting")
	plugin._paint(Vector2i(-1, 1))
	plugin._commit_stroke("Regression expand and paint")
	suite.check(expansion_map.map_origin.x < 0
		and expansion_map.tile_id(Vector2i(-2, 0)) == "ground_forest"
		and expansion_map.world_center(Vector2i(1, 1)).is_equal_approx(stable_world)
		and expansion_map.spawn_cell == Vector2i(1, 1)
		and expansion_map.stairs == [{"cell": Vector2i(2, 2), "direction": 1, "layer": 0}]
		and _top_visual(plugin.builder, Vector2i(-2, 0)) != null,
		"expanded brush keeps existing cells stairs spawn and world positions")
	var expansion_history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(expansion_map))
	expansion_history.undo()
	suite.check(expansion_map.map_origin == Vector2i.ZERO
		and expansion_map.map_size == Vector2i(4, 4)
		and expansion_map.world_center(Vector2i(1, 1)).is_equal_approx(stable_world),
		"one undo restores both painted cells and original map bounds")
	expansion_history.redo()
	suite.check(expansion_map.map_origin.x < 0
		and expansion_map.tile_id(Vector2i(-2, 0)) == "ground_forest",
		"one redo reapplies expansion and paint")
	plugin.current_path = previous_path
	plugin.active_layer = 0
	plugin.tile_turns = 0
	plugin.data = original
	plugin.builder.level_data = original
	plugin.builder.rebuild()
	tools.reset()

func _top_visual(builder: TerrainBuilder, cell: Vector2i, layer := -1) -> MeshInstance3D:
	for child in builder.generated.get_children():
		if child is MeshInstance3D and cell in child.get_meta("terrain_cells", []) \
				and (layer < 0 or child.get_meta("terrain_layer", -1) == layer):
			return child
	return null
