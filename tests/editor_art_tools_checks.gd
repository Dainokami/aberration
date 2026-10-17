@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var old_builder: TerrainBuilder = plugin.builder
	var old_data: LevelData = plugin.data
	plugin._disable_2_5d_view()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.own_world_3d = true
	plugin.get_tree().root.add_child(viewport)
	var map := LevelData.new()
	map.setup_blank(Vector2i(6, 6))
	for y in 6:
		for x in 6:
			map.set_layer(Vector2i(x, y), 0, {"tile_id": "grass"})
	var builder := TerrainBuilder.new()
	builder.level_data = map
	builder.show_grid = false
	viewport.add_child(builder)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14
	camera.position = Vector3(0, 16, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	plugin.builder = builder
	plugin.data = map
	plugin._make_preview()
	var tool = plugin.world_tools.detail_tools
	plugin.tabs.current_tab = 5
	var upright_set: int = tool.paths.find("res://data/details/painted_upright.tres")
	tool.sets.select(upright_set)
	tool.refresh_palette()
	tool.mode.selected = 1
	tool.palette.select(0)
	var detail_set: DetailSet = tool.current_set()
	var selected_variant: String = detail_set.variants[tool.visible_variants[0]]["id"]
	var single_records: Array[Dictionary] = tool.records_at(
		map.world_center(Vector2i(2, 2)), "single_scatter", 12345)
	var only_selected := not single_records.is_empty()
	for record in single_records:
		only_selected = only_selected and record["variant"] == selected_variant
	suite.check(tool.scatter_source.selected == 1 and tool.selection_controls.visible
		and only_selected, "single scatter is the default and uses the selected detail card")
	tool.size_input.value = 1.4
	var resized_records: Array[Dictionary] = tool.records_at(
		map.world_center(Vector2i(2, 2)), "resized_scatter", 12345)
	var resized := resized_records.size() == single_records.size() and not resized_records.is_empty()
	for i in mini(resized_records.size(), single_records.size()):
		resized = resized and is_equal_approx(
			float(resized_records[i]["scale"]) / float(single_records[i]["scale"]), 1.4)
	var old_seed := int(tool.seed_input.value)
	tool._randomize_seed()
	var new_seed := int(tool.seed_input.value)
	suite.check(resized, "committed detail size applies to the next scatter")
	suite.check(old_seed != new_seed and tool.info.text.contains("种子 %d" % new_seed),
		"random seed button changes and displays the active scatter seed")
	tool.sets.select(tool.paths.find("res://data/details/painted_flat.tres"))
	tool.refresh_palette()
	tool.palette.select(0)
	tool.size_input.value = 3.4
	var edge := map.world_center(Vector2i.ZERO)
	var invalid_large: Array[Dictionary] = tool.records_at(edge, "invalid_large", 24680)
	tool.preview_at(edge)
	suite.check(invalid_large.is_empty() and plugin.status.text.contains("缺少完整")
		and tool.radius.tooltip_text.contains("不会裁切"),
		"oversized ground detail shows a support error instead of silently disappearing")
	tool.clear_preview()
	tool.sets.select(upright_set)
	tool.refresh_palette()
	tool.palette.select(0)
	tool.size_input.value = 1.4
	tool.search.text = "__no_matching_detail__"
	tool.refresh_palette()
	tool.scatter_source.selected = 0
	var mixed_records: Array[Dictionary] = tool.records_at(
		map.world_center(Vector2i(2, 2)), "mixed_scatter", 12345)
	var mixed_variants := {}
	for record in mixed_records:
		mixed_variants[record["variant"]] = true
	suite.check(not tool.selection_controls.visible and tool.info.text.contains("混合全部")
		and mixed_variants.size() > 1, "mix all hides detail cards and scatters multiple variants")
	var selection_style := tool.selection_panel.get_theme_stylebox("panel") as StyleBoxFlat
	suite.check(selection_style != null and selection_style.border_width_left > 0
		and tool.info_caption.get_theme_color("font_color") != Color.WHITE,
		"selected detail parameters use a distinct framed information panel")
	suite.check(tool.advanced.text.contains("更多设置")
		and tool.seed_input.tooltip_text.contains("按 Enter")
		and tool.apply_hint.text == "修改后按回车应用到下一笔"
		and tool.random_seed_button.text == "随机"
		and tool.reload_button.text == "重新加载素材"
		and tool.scatter_source.buttons[1].has_theme_stylebox_override("pressed"),
		"detail advanced terms and scatter choices are visually explicit")
	tool.size_input.value = 1
	tool.search.text = ""
	tool.refresh_palette()
	tool.scatter_source.selected = 1
	tool.mode.selected = 0
	tool.palette.select(0)
	var cell := Vector2i(2, 2)
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var before := map.clone_data()
	click(plugin, camera, camera.unproject_position(map.world_center(cell)))
	suite.check(map.details.size() == 1 and map.objects.is_empty() \
		and map.columns == before["columns"], "detail click only modifies the independent detail array")
	var history := plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	var painted := map.details.duplicate(true)
	history.undo()
	suite.check(map.clone_data() == before and builder.detail_renderer.groups.is_empty(),
		"detail undo restores data and removes actual rendered batches")
	history.redo()
	suite.check(map.details == painted and not builder.detail_renderer.groups.is_empty(),
		"detail redo restores the exact random transforms and batches")
	tool.mode.selected = 2
	click(plugin, camera, camera.unproject_position(map.world_center(cell)))
	suite.check(map.details.is_empty() and map.columns == before["columns"],
		"detail eraser preserves terrain")
	history.undo()
	suite.check(map.details == painted, "detail erase undo restores same instance IDs")

	plugin.tabs.current_tab = 0
	plugin.mode_select.selected = 0
	plugin.active_layer = 1
	plugin.tile_list.select(0)
	plugin.touched.clear()
	plugin._begin_stroke()
	plugin._paint(cell)
	plugin._commit_stroke("美术测试抬高支撑")
	suite.check(map.details == painted and builder.detail_renderer.groups.is_empty(),
		"terrain cover retains detail anchors and skips their rendered batches")
	history.undo()
	suite.check(map.details == painted and map.top_layer(cell) == 0,
		"terrain undo restores details together with the column")
	history.redo()
	plugin.mode_select.selected = 2
	plugin.active_layer = 0
	plugin.erase_select.selected = 0
	plugin.touched.clear()
	plugin.last_stroke_cell = Vector2i(-999, -999)
	plugin._begin_stroke()
	plugin._paint(cell)
	plugin._commit_stroke("美术测试擦除支撑")
	suite.check(map.details.is_empty(), "terrain erase removes details on the deleted top")
	history.undo()
	suite.check(map.details.size() == 1 and map.details[0]["anchor_layer"] == 0,
		"terrain erase undo restores removed detail anchors")

	# A slice cap must block decoration placement instead of placing on an invisible top.
	plugin.tabs.current_tab = 5
	tool.mode.selected = 0
	builder.set_slice_layer(0)
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var slice_before := map.clone_data()
	click(plugin, camera, camera.unproject_position(map.world_center(cell, 0)))
	suite.check(map.clone_data() == slice_before and plugin.status.text.contains("切片"),
		"actual detail input rejects temporary slice caps")
	builder.set_slice_layer(-1)

	# Actual object clicks should discover the top of a previously placed rock.
	plugin.tabs.current_tab = 1
	var objects = plugin.world_tools
	objects.object_mode.selected = 0
	objects.refresh_library()
	objects.scale_input.value = 1
	objects.yaw_input.value = 0
	var before_supplement := map.clone_data()
	var supplements: Array[String] = ["painted_climbingrock", "painted_climbingrock_alt",
		"painted_rock_alt", "painted_decayrock_alt"]
	for i in supplements.size():
		var path: String = "res://assets/generated/" + supplements[i] + "/definition.tres"
		var index: int = objects.paths.find(path)
		suite.check(index >= 0 and objects.library.get_item_icon(index) != null,
			"remaining art has an actual editor library card " + supplements[i])
		if index < 0:
			continue
		objects.library.select(index)
		await plugin.get_tree().physics_frame
		await plugin.get_tree().physics_frame
		click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(i, 4))))
		suite.check(map.objects.size() == i + 1 and map.objects.back()["definition"] == path,
			"viewport places remaining art resource " + supplements[i])
	for i in supplements.size():
		history.undo()
	suite.check(map.clone_data() == before_supplement,
		"remaining art placement undo restores the complete original map")
	var manifest_1015: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/derived_art/scene_pack_20261015/manifest.json"))
	for entry: Dictionary in manifest_1015["entries"]:
		var path: String = "res://assets/generated/" + str(entry["id"]) + "/definition.tres"
		var index: int = objects.paths.find(path)
		suite.check(index >= 0 and objects.library.get_item_icon(index) != null,
			"1015 art appears in editor library " + str(entry["name"]))
	for id: String in ["painted_traction_rock_01", "painted_fissured_rock"]:
		var path := "res://assets/generated/" + id + "/definition.tres"
		objects.library.select(objects.paths.find(path))
		await plugin.get_tree().physics_frame
		await plugin.get_tree().physics_frame
		click(plugin, camera, camera.unproject_position(map.world_center(Vector2i(3, 4))))
		suite.check(map.objects.size() == 1 and map.objects[0]["definition"] == path,
			"1015 viewport placement " + id)
		history.undo()
	suite.check(map.clone_data() == before_supplement, "1015 viewport undo preserves original map")
	var rock: int = objects.paths.find("res://assets/generated/painted_rock/definition.tres")
	objects.library.select(rock)
	objects.scale_input.value = 1
	objects.yaw_input.value = 0
	var rock_cell := Vector2i(4, 3)
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	click(plugin, camera, camera.unproject_position(map.world_center(rock_cell)))
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	click(plugin, camera, camera.unproject_position(map.world_center(rock_cell) + Vector3.UP * 2))
	suite.check(map.objects.size() == 2 and map.objects[1].get("support_id") == map.objects[0].get("id") \
		and map.objects[1]["position"].y == 4, "viewport clicks stack rocks with a persistent host ID")
	var graph := map.clone_data()
	objects.selected_id = str(map.objects[0]["id"])
	objects.delete_selected()
	suite.check(map.objects.is_empty(), "deleting root object removes its dependents")
	history.undo()
	suite.check(map.clone_data() == graph, "object undo restores the entire support graph")

	# Verify history is bound to its original map, even while another map is active.
	var other := LevelData.new()
	other.setup_blank()
	plugin.data = other
	history.undo()
	suite.check(other.details.is_empty() and other.objects.is_empty() and map.objects.size() == 1,
		"art tool history cannot write into a newly selected map")
	plugin.world_tools.reset()
	plugin.builder = old_builder
	plugin.data = old_data
	plugin.tabs.current_tab = 0
	plugin.mode_select.selected = 0
	plugin.active_layer = 0
	plugin._make_preview()
	viewport.queue_free()
	await plugin.get_tree().process_frame

func click(plugin: EditorPlugin, camera: Camera3D, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	plugin._forward_3d_gui_input(camera, event)
	event.pressed = false
	plugin._forward_3d_gui_input(camera, event)
