@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var original: LevelData = plugin.data
	var map := LevelData.new()
	map.setup_blank()
	plugin.data = map
	plugin.builder.level_data = map
	plugin.builder.rebuild()
	var ids := ["ground_forest", "ground_stone", "decal_corruption", "decal_marsh"]
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
		var top := plugin.builder.generated.get_node("Top_%d_%d" % [cell.x, cell.y]) as MeshInstance3D
		var mat := top.material_override as StandardMaterial3D
		var definition := TileRegistry.find(ids[i])
		suite.check(map.tile_id(cell) == ids[i] and mat != null and
			mat.albedo_texture.resource_path == definition.texture_path,
			"painted mesh uses imported texture " + ids[i])

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
	plugin.height_select.selected = 2
	plugin.tile_turns = 1
	var before_replace := map.clone_data()
	plugin.touched.clear()
	plugin._paint_single(Vector2i(4, 4), 0)
	plugin._commit_external(before_replace, map.clone_data(), "Replace height and rotation")
	suite.check(map.elevation(Vector2i(4, 4)) == 2 and map.get_cell(Vector2i(4, 4))["rotation"] == 1,
		"replace existing ground changes height and rotation")
	suite.check(is_equal_approx(map.objects[0]["position"].y, 4.0),
		"supported tree follows replacement height")
	var rotated_top := plugin.builder.generated.get_node("Top_4_4") as MeshInstance3D
	suite.check(is_equal_approx(rotated_top.rotation.y, -PI / 2),
		"rotated ground mesh uses stored rotation")
	plugin._update_preview(Vector2i(4, 4))
	var display := plugin.preview.get_child(0) as TerrainBuilder
	var preview_top := display.generated.get_node("Top_0_0") as MeshInstance3D
	suite.check(not display.build_collision and preview_top.position.y > 3.9 and
		is_equal_approx(preview_top.rotation.y, -PI / 2) and
		(preview_top.material_override as StandardMaterial3D).albedo_texture != null,
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
		"terrain": 0, "tile_id": "decal_corruption"})
	plugin.builder.level_data = transition_map
	plugin.builder.rebuild()
	var transitions: Array[Node] = plugin.builder.generated.find_children(
		"Transition_*", "MeshInstance3D", false, false)
	suite.check(transitions.size() == 1 and
		transitions[0].get_meta("transition_upper") == "decal_corruption" and
		transitions[0].get_meta("transition_lower") == "ground_forest",
		"same-height edge mask follows terrain priority")
	var transition_material := transitions[0].material_override as ShaderMaterial
	suite.check(transition_material.get_shader_parameter("edge_mask") is Texture2D,
		"transition uses configured/generated mask")
	transition_map.get_cell(Vector2i(2, 1))["height"] = 1
	plugin.builder.rebuild()
	suite.check(plugin.builder.generated.find_children("Transition_*", "MeshInstance3D", false, false).is_empty() and
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
	plugin.current_path = previous_path
	plugin.height_select.selected = 0
	plugin.tile_turns = 0
	plugin.data = original
	plugin.builder.level_data = original
	plugin.builder.rebuild()
	tools.reset()
