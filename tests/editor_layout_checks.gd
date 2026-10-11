@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var real_builder: TerrainBuilder = plugin.builder
	var real_data: LevelData = plugin.data
	plugin.builder = null
	plugin.data = null
	plugin._new_map()
	suite.check(plugin.data == null and plugin.status.text.contains("TerrainBuilder"),
		"new map without selected builder is rejected without partial data")
	plugin.builder = real_builder
	plugin.data = real_data
	var removed_builder := TerrainBuilder.new()
	removed_builder.level_data = LevelData.new()
	removed_builder.level_data.setup_blank()
	plugin.get_tree().root.add_child(removed_builder)
	plugin.builder = removed_builder
	plugin.data = removed_builder.level_data
	plugin.pending_action = "new"
	removed_builder.free()
	plugin._confirm_discard()
	suite.check(plugin.builder == null and plugin.data == null and
		plugin.pending_action.is_empty(), "dialog callback survives deleted builder")
	plugin.builder = real_builder
	plugin.data = real_data
	suite.check(plugin.mode_select.buttons.size() == 4 and not plugin.mode_select.buttons.has(1),
		"terrain has four horizontal modes and no height mode")
	for mode in [0, 2, 3, 4]:
		plugin.mode_select.selected = mode
		var correct := true
		for control: Control in plugin.ground_controls:
			correct = correct and control.visible == (mode == 0)
		for control: Control in plugin.brush_controls:
			correct = correct and control.visible == (mode in [0, 2])
		for control: Control in plugin.direction_controls:
			correct = correct and control.visible == (mode in [0, 3])
		var pressed := 0
		for button: Button in plugin.mode_select.buttons.values():
			if button.button_pressed:
				pressed += 1
		suite.check(correct and pressed == 1, "terrain mode controls and single selection %d" % mode)
	plugin.mode_select.selected = 0
	var tools = plugin.world_tools
	for mode in [0, 1]:
		tools.object_mode.selected = mode
		var correct := true
		for control: Control in tools.placement_controls:
			correct = correct and control.visible == (mode == 0)
		for control: Control in tools.adjustment_controls:
			correct = correct and control.visible == (mode == 1)
		suite.check(correct, "object mode filters controls %d" % mode)
	tools.clipboard = plugin.data.objects[0].duplicate(true)
	tools.paste_selected()
	suite.check(tools.object_mode.selected == 0 and tools.library.visible and
		not tools.selected_label.visible, "paste switches from adjust to placement")
	tools.clipboard.clear()
	var camera := Camera3D.new()
	plugin.get_tree().root.add_child(camera)
	camera.position = Vector3(2, 8, 7)
	var initial := camera.transform
	plugin.editing_camera = camera
	plugin._fixed_view_pressed()
	var profile := load("res://data/art_profile.tres") as ArtProfile
	suite.check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and
		camera.fov == profile.field_of_view and
		camera.global_basis.is_equal_approx(profile.camera_basis()),
		"2.5D reset uses front perspective camera orientation and FOV")
	plugin.reset_view_frames = 0
	camera.global_transform = initial
	suite.check(camera.transform.is_equal_approx(initial),
		"camera remains freely movable after reset")
	camera.queue_free()
	plugin.editing_camera = null
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if viewport != null and viewport.get_camera_3d() != null:
		plugin._fixed_view_pressed()
		for frame in 4:
			await plugin.get_tree().process_frame
		var actual: Camera3D = plugin.editing_camera
		suite.check(actual.projection == Camera3D.PROJECTION_PERSPECTIVE and
			actual.global_basis.is_equal_approx(profile.camera_basis()),
			"actual editor camera receives perspective reset")
		suite.check(plugin.reset_view_frames == 0 and not plugin.fixed_view_button.toggle_mode,
			"2.5D button does not lock editor navigation")

	# Test the native ItemList's actual content layout, not just property values.
	for source: ItemList in [plugin.tile_list, plugin.world_tools.library, plugin.world_tools.prefab_library]:
		suite.check(source.auto_height and source.custom_minimum_size.y == 0,
			"palette uses content height " + str(source.fixed_icon_size))
	var list := ItemList.new()
	list.auto_height = true
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(80, 72)
	list.max_columns = 0
	list.same_column_width = true
	list.size = Vector2(300, 0)
	plugin.get_tree().root.add_child(list)
	var image := Image.create(80, 72, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	var icon := ImageTexture.create_from_image(image)
	list.add_item("Tile", icon)
	for i in 4:
		await plugin.get_tree().process_frame
	var small := list.get_combined_minimum_size().y
	for i in 15:
		list.add_item("Tile", icon)
	for i in 4:
		await plugin.get_tree().process_frame
	var tall := list.get_combined_minimum_size().y
	suite.check(tall > small, "palette height grows with content")
	list.size.x = 600
	for i in 4:
		await plugin.get_tree().process_frame
	suite.check(list.get_combined_minimum_size().y < tall, "palette reflows when widened")
	list.clear()
	list.add_item("Tile", icon)
	for i in 4:
		await plugin.get_tree().process_frame
	suite.check(list.get_combined_minimum_size().y <= small, "palette shrinks after filtering")
	list.queue_free()
