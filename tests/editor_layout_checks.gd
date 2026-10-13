@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	suite.check(plugin.launcher_button != null and plugin.launcher_button.text == "关卡编辑器",
		"persistent toolbar launcher exists")
	suite.check(plugin.editor_dock != null and plugin.editor_dock.title == "关卡编辑器",
		"Godot 4.7 EditorDock is registered")
	suite.check(plugin.dock_started_closed and
		plugin.editor_dock.default_slot == EditorDock.DOCK_SLOT_RIGHT_BR and
		plugin.editor_dock.transient and plugin.editor_dock.closable,
		"level editor starts closed and opens in the right dock")
	var placement_style := plugin.placement_panel.get_theme_stylebox("panel") \
		as StyleBoxFlat
	var tint_style := plugin.tint_panel.get_theme_stylebox("panel") as StyleBoxFlat
	suite.check(placement_style != null and tint_style != null and
		not placement_style.border_color.is_equal_approx(tint_style.border_color),
		"terrain placement and tint controls use distinct colored frames")
	var discoverable := plugin._find_terrain_builder(EditorInterface.get_edited_scene_root()) != null
	if not discoverable:
		var packed := load(plugin.EDITOR_WORKSPACE_SCENE) as PackedScene
		var workspace := packed.instantiate() if packed != null else null
		discoverable = plugin._find_terrain_builder(workspace) != null
		if workspace != null:
			workspace.free()
	suite.check(discoverable,
		"workspace builder is discoverable without scene-tree selection")
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
	suite.check(plugin.tabs.get_child_count() == 5 and
		plugin.tabs.get_child(4).name == "视角", "view settings tab exists")
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
	var clipboard_source: LevelData = plugin.data
	if clipboard_source.objects.is_empty():
		clipboard_source = load("res://data/levels/objects_acceptance.tres") as LevelData
	tools.clipboard = clipboard_source.objects[0].duplicate(true)
	tools.paste_selected()
	suite.check(tools.object_mode.selected == 0 and tools.library.visible and
		not tools.selected_label.visible, "paste switches from adjust to placement")
	tools.clipboard.clear()
	var camera := Camera3D.new()
	plugin.get_tree().root.add_child(camera)
	camera.position = Vector3(2, 8, 7)
	var initial := camera.transform
	plugin._disable_2_5d_view()
	plugin.editing_camera = camera
	plugin._fixed_view_pressed()
	var profile := load("res://data/art_profile.tres") as ArtProfile
	suite.check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and
		camera.fov == profile.field_of_view and
		camera.global_basis.is_equal_approx(profile.camera_basis()),
		"2.5D mode uses front perspective camera orientation and FOV")
	suite.check(plugin.fixed_view_active and plugin.fixed_view_button.button_pressed,
		"2.5D mode stays active after entry")
	plugin._top_view_pressed()
	var expected_top_basis := Basis.looking_at(
		Vector3.DOWN, Vector3(0.0, 0.0, -1.0))
	suite.check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		and camera.global_basis.is_equal_approx(expected_top_basis)
		and plugin.top_view_button.button_pressed,
		"top mode uses a north-up orthographic camera")
	plugin._free_view_pressed()
	suite.check(camera.transform.is_equal_approx(initial)
		and plugin.free_view_button.button_pressed
		and not plugin.fixed_view_active,
		"free mode restores previous editor camera")
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
			"actual editor camera receives fixed perspective mode")
		suite.check(plugin.fixed_view_active and plugin.fixed_view_button.toggle_mode,
			"2.5D button is active fixed-navigation mode")
		var old_center: Vector3 = plugin.view_pan_offset
		plugin.view_move_keys[KEY_D] = true
		plugin._process(0.5)
		plugin.view_move_keys[KEY_D] = false
		suite.check(plugin.view_pan_offset.x > old_center.x,
			"WASD pans fixed view center")
		var old_distance: float = plugin._effective_distance()
		plugin._zoom_fixed_view(0.88)
		suite.check(plugin._effective_distance() < old_distance,
			"mouse wheel zoom changes fixed view distance")
		plugin._disable_2_5d_view()
	var live := Camera3D.new()
	plugin.get_tree().root.add_child(live)
	plugin.editing_camera = live
	plugin.apply_view_parameters(52, 18, 20, 1.5)
	suite.check(live.projection == Camera3D.PROJECTION_PERSPECTIVE and
		is_equal_approx(live.fov, 52) and
		is_equal_approx(live.global_position.distance_to(
			plugin.builder.global_position + Vector3.UP * 1.5), 20.0) and
		live.global_basis.is_equal_approx(
			Basis.looking_at(-Vector3(0, sin(deg_to_rad(18)), cos(deg_to_rad(18))), Vector3.UP)),
		"view parameters apply FOV pitch distance and target height live")
	plugin._disable_2_5d_view()
	live.queue_free()
	plugin.preview_fov = -1
	plugin.preview_pitch = -1
	plugin.preview_distance = -1
	plugin.preview_target_height = INF
	await _check_terrain_pick_and_stair_preview(
		plugin, suite, real_builder, real_data, profile)

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

func _check_terrain_pick_and_stair_preview(plugin: EditorPlugin,
		suite: RefCounted, real_builder: TerrainBuilder, real_data: LevelData,
		profile: ArtProfile) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	plugin.get_tree().root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var pick_data := LevelData.new()
	pick_data.setup_blank(Vector2i(4, 4))
	for y in pick_data.map_size.y:
		for x in pick_data.map_size.x:
			pick_data.set_cell(Vector2i(x, y), {
				"exists": true,
				"terrain": 0,
				"tile_id": "grass",
				"height": 1 if y < 2 else 0,
				"rotation": 0,
			})
	var pick_builder := TerrainBuilder.new()
	pick_builder.level_data = pick_data
	pick_builder.show_grid = false
	pick_builder.build_collision = true
	world.add_child(pick_builder)
	var camera := Camera3D.new()
	world.add_child(camera)
	profile.configure(camera, Vector3.ZERO)
	camera.current = true
	plugin.builder = pick_builder
	plugin.data = pick_data
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var high := Vector2i(1, 1)
	var low := Vector2i(1, 2)
	var high_center := pick_data.world_center(high)
	var low_center := pick_data.world_center(low)
	var boundary_z := (high_center.z + low_center.z) * 0.5
	var picked_cliff := true
	for height in [1.7, 1.0, 0.25]:
		var screen := camera.unproject_position(
			Vector3(high_center.x, height, boundary_z))
		picked_cliff = picked_cliff and plugin._pick(camera, screen) == high
	suite.check(picked_cliff
		and plugin._pick(camera, camera.unproject_position(high_center)) == high
		and plugin._pick(camera, camera.unproject_position(low_center)) == low,
		"terrain picking follows visible tops and cliff faces")
	plugin.mode_select.selected = 3
	plugin.stair_direction = 0
	plugin._make_preview()
	plugin._update_preview(low)
	var display: TerrainBuilder = null
	if plugin.preview.get_child_count() > 0:
		display = plugin.preview.get_child(0) as TerrainBuilder
	var preview_steps := []
	if display != null:
		for node in display.find_children("*", "MeshInstance3D", true, false):
			if node.has_meta("stair_step"):
				preview_steps.append(node)
	preview_steps.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D):
		return int(a.get_meta("stair_step")) < int(b.get_meta("stair_step")))
	var preview_rises := preview_steps.size() == 10
	var previous_y := -INF
	for step: MeshInstance3D in preview_steps:
		preview_rises = preview_rises and step.position.y > previous_y
		previous_y = step.position.y
	suite.check(display != null and not display.build_collision
		and preview_steps.size() == 10 and preview_rises,
		"stair brush previews the final rising 3D staircase")
	plugin.mode_select.selected = 0
	plugin.builder = real_builder
	plugin.data = real_data
	plugin._make_preview()
	viewport.queue_free()
