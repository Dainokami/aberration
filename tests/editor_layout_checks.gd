@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var right_delete_before: bool = plugin.default_right_delete.button_pressed
	plugin.default_right_delete.set_pressed_no_signal(true)
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
	suite.check(plugin.mode_select.buttons.size() == 3 and not plugin.mode_select.buttons.has(1),
		"terrain has three horizontal modes and no height mode")
	suite.check(plugin.tabs.get_child_count() == 7 and
		plugin.tabs.get_child(4).name == "视角" and plugin.tabs.get_child(5).name == "细节"
		and plugin.tabs.get_child(6).name == "怪物",
		"monster tab appended while preserving all existing tab indices")
	for mode in [0, 3, 4]:
		plugin.mode_select.selected = mode
		var correct := true
		for control: Control in plugin.ground_controls:
			correct = correct and control.visible == (mode == 0)
		for control: Control in plugin.brush_controls:
			correct = correct and control.visible == (mode in [0, 2])
		for control: Control in plugin.layer_controls:
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
	var before_free := camera.transform
	plugin._free_view_pressed()
	suite.check(camera.transform.is_equal_approx(before_free)
		and plugin.free_view_button.button_pressed
		and plugin.free_view_active and not plugin.fixed_view_active,
		"free mode preserves current camera instead of jumping to an old position")
	plugin.view_move_keys[KEY_W] = true
	plugin._move_free_view(camera, 0.25)
	plugin._clear_view_input()
	plugin._apply_fixed_view()
	suite.check((camera.position - before_free.origin).dot(before_free.basis.y) > 1.0,
		"free navigation from top view moves visibly across the screen")
	plugin._disable_2_5d_view()
	suite.check(camera.transform.is_equal_approx(initial),
		"leaving terrain navigation restores native editor camera")
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
		var focus := plugin.get_tree().root.gui_get_focus_owner()
		if focus != null:
			focus.release_focus()
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
		await _check_free_navigation(plugin, suite, actual)
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
	await _check_layer_popups(plugin, suite)
	plugin.default_right_delete.set_pressed_no_signal(right_delete_before)

func _check_free_navigation(plugin: EditorPlugin, suite: RefCounted, camera: Camera3D) -> void:
	var before := camera.global_transform
	plugin._free_view_pressed()
	suite.check(camera.global_transform.is_equal_approx(before), "perspective free view retains the current pose")
	plugin._enable_initial_view(plugin.builder)
	suite.check(plugin.free_view_active, "delayed default view cannot override an explicit free view")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	var handled: int = plugin._forward_3d_gui_input(camera, event)
	plugin._process(0.25)
	event.pressed = false
	plugin._forward_3d_gui_input(camera, event)
	var moved := camera.global_transform
	suite.check(handled == EditorPlugin.AFTER_GUI_INPUT_STOP
		and (moved.origin - before.origin).dot(-before.basis.z) > 1.0,
		"free view W moves along the viewing direction without holding a mouse button")
	for frame in 4:
		await plugin.get_tree().process_frame
	suite.check(camera.global_transform.is_equal_approx(moved),
		"native editor updates do not reset the free camera")
	event.physical_keycode = KEY_D
	event.pressed = true
	plugin._forward_3d_gui_input(camera, event)
	plugin._process(0.25)
	event.pressed = false
	plugin._input(event)
	suite.check((camera.global_position - moved.origin).dot(moved.basis.x) > 1.0
		and not plugin.view_move_keys[KEY_D], "free D strafes and key release outside viewport stops movement")
	var before_zoom := camera.global_position
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	plugin._forward_3d_gui_input(camera, wheel)
	suite.check((camera.global_position - before_zoom).dot(-camera.global_basis.z) > 1.0,
		"free wheel zoom makes a visible forward movement")
	before_zoom = camera.global_position
	wheel.shift_pressed = true
	plugin._forward_3d_gui_input(camera, wheel)
	suite.check((camera.global_position - before_zoom).dot(-camera.global_basis.z) > 1.0,
		"Shift wheel retains ordinary camera zoom with no air placement mode")
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.alt_pressed = true
	drag.relative = Vector2(32, 12)
	var before_turn := camera.global_basis
	plugin._forward_3d_gui_input(camera, drag)
	suite.check(not camera.global_basis.is_equal_approx(before_turn),
		"free Alt-right drag changes the viewing direction")
	var magnify := InputEventMagnifyGesture.new()
	magnify.factor = 1.15
	var before_pinch := camera.global_position
	plugin._forward_3d_gui_input(camera, magnify)
	suite.check((camera.global_position - before_pinch).dot(-camera.global_basis.z) > 0,
		"mac trackpad pinch zooms the free view")
	var field := LineEdit.new()
	plugin.get_tree().root.add_child(field)
	field.grab_focus()
	event.physical_keycode = KEY_W
	event.pressed = true
	before = camera.global_transform
	plugin._forward_3d_gui_input(camera, event)
	plugin._process(0.25)
	suite.check(camera.global_transform.is_equal_approx(before)
		and not plugin.view_move_keys[KEY_W], "typing into a field cannot move the free camera")
	field.release_focus()
	field.queue_free()
	await _check_free_mode_badge(plugin, suite, camera)

func _check_free_mode_badge(plugin: EditorPlugin, suite: RefCounted, camera: Camera3D) -> void:
	# Use the actual overlay callback even on the headless renderer.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plugin.get_tree().root.add_child(overlay)
	plugin._forward_3d_force_draw_over_viewport(overlay)
	var badge := overlay.get_node("TerrainEditModeBadge") as PanelContainer
	var label := badge.get_node("State") as Label
	suite.check(badge.visible and label.text == "摆放/删除中"
		and label.get_theme_color("font_color") == plugin.EDIT_MODE_COLOR
		and badge.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"free viewport starts with a red, mouse-transparent placement/deletion badge")
	var alt := InputEventKey.new()
	alt.keycode = KEY_ALT
	alt.pressed = true
	plugin._forward_3d_gui_input(camera, alt)
	suite.check(label.text == "移动视角中"
		and label.get_theme_color("font_color") == plugin.NAVIGATION_MODE_COLOR,
		"pressing Alt updates the green navigation badge without mouse motion")
	var before: Dictionary = plugin.data.clone_data()
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.alt_pressed = true
		click.position = camera.unproject_position(plugin.data.world_center(plugin.data.spawn_cell))
		click.pressed = true
		plugin._forward_3d_gui_input(camera, click)
		click.pressed = false
		plugin._forward_3d_gui_input(camera, click)
	suite.check(plugin.data.clone_data() == before and not plugin.drawing,
		"Alt navigation cannot place or delete terrain")
	alt.pressed = false
	plugin._input(alt)
	suite.check(label.text == "摆放/删除中"
		and label.get_theme_color("font_color") == plugin.EDIT_MODE_COLOR,
		"Alt release outside the viewport immediately restores the red badge")
	alt.pressed = true
	plugin._input(alt)
	plugin._clear_view_input()
	suite.check(label.text == "摆放/删除中" and not plugin._alt_navigation,
		"window focus loss clears the navigation modifier and stale green badge")
	plugin._enable_2_5d_view()
	suite.check(not badge.visible, "camera mode badge is hidden outside free view")
	plugin._free_view_pressed()
	suite.check(badge.visible and label.text == "摆放/删除中",
		"returning to free view restores the current badge")
	plugin.default_right_delete.set_pressed_no_signal(false)
	plugin._refresh_view_mode_badges()
	suite.check(label.text == "移动视角中"
		and plugin._right_button_navigates(false) and plugin._right_button_deletes(true),
		"disabled switch uses right-button navigation and Alt-right deletion")
	alt.pressed = true
	plugin._input(alt)
	suite.check(label.text == "摆放/删除中", "disabled switch reverses the Alt badge states")
	alt.pressed = false
	plugin._input(alt)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.relative = Vector2(16, 8)
	var pose := camera.transform
	plugin._forward_3d_gui_input(camera, drag)
	suite.check(not camera.transform.is_equal_approx(pose),
		"disabled switch rotates the free camera with ordinary right drag")
	plugin.default_right_delete.set_pressed_no_signal(true)
	plugin._refresh_view_mode_badges()
	overlay.free()
	if "--capture-interaction" in OS.get_cmdline_user_args():
		# Capture the native viewport badges, with no synthetic overlay remaining.
		for state in [false, true]:
			alt.pressed = state
			plugin._input(alt)
			plugin.update_overlays()
			for frame in 3:
				await plugin.get_tree().process_frame
			await RenderingServer.frame_post_draw
			var suffix := "navigation" if state else "placement"
			plugin.get_tree().root.get_texture().get_image().save_png(
				"/tmp/aberration-editor-%s-mode.png" % suffix)
		alt.pressed = false
		plugin._input(alt)

func _check_layer_popups(plugin: EditorPlugin, suite: RefCounted) -> void:
	var root := plugin.get_tree().root
	var capture := "--capture-interaction" in OS.get_cmdline_user_args()
	if capture:
		plugin.editor_dock.make_visible()
		plugin.tabs.current_tab = 0
		for frame in 4:
			await plugin.get_tree().process_frame
	suite.check(plugin.dock_root.find_child("PlacementLayer", true, false) == null
		and plugin.mode_select.buttons.size() == 3
		and plugin.mode_select.buttons[0].text == "选地块"
		and not plugin.mode_select.buttons.has(2),
		"terrain dock merges placement and erasure and removes manual placement layers")
	for option: OptionButton in [plugin.slice_select]:
		var popup := option.get_popup()
		if capture:
			option.show_popup()
		else:
			popup.popup(Rect2i(0, 0, 300, 1))
		for frame in 2:
			await plugin.get_tree().process_frame
		var scroll := _popup_scroll(popup)
		print("POPUP SIZE ", option.name, " actual=", popup.size, " max=", popup.max_size,
			" scroll=", scroll)
		suite.check(popup.size.y <= popup.max_size.y and popup.max_size.y > 0
			and popup.max_size.y < plugin.get_tree().root.size.y * 0.5
			and scroll != null and scroll.get_v_scroll_bar().visible,
			"layer popup stays below half the window and offers scrolling: " + option.name)
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/terrain-%s-panel.png" % option.name)
			popup.get_texture().get_image().save_png("/tmp/terrain-%s-popup.png" % option.name)
		popup.set_focused_item(popup.item_count - 1)
		for frame in 2:
			await plugin.get_tree().process_frame
		suite.check(scroll != null and scroll.scroll_vertical > 0,
			"last layer remains reachable in a capped popup: " + option.name)
		popup.hide()

func _popup_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children(true):
		var found := _popup_scroll(child)
		if found != null:
			return found
	return null

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
	profile.configure(camera, Vector3.UP * LevelData.ELEVATION_STEP)
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
			Vector3(high_center.x, low_center.y + height, boundary_z))
		picked_cliff = picked_cliff and plugin._pick(camera, screen) == high \
			and plugin.picked_layer == 1
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
	pick_builder.free()
	var sparse_data := LevelData.new()
	sparse_data.setup_blank(Vector2i(8, 8))
	var anchor := Vector2i(3, 3)
	var front := anchor + Vector2i(0, 1)
	sparse_data.set_layer(anchor, 0, {"tile_id": "grass"})
	var sparse_builder := TerrainBuilder.new()
	sparse_builder.level_data = sparse_data
	sparse_builder.show_grid = false
	sparse_builder.build_collision = true
	world.add_child(sparse_builder)
	plugin.builder = sparse_builder
	plugin.data = sparse_data
	plugin.tabs.current_tab = 0
	plugin.mode_select.selected = 0
	plugin.brush_select.selected = 0
	plugin.active_layer = 0
	plugin._make_preview()
	await plugin.get_tree().physics_frame
	await plugin.get_tree().physics_frame
	var front_base := sparse_data.world_center(front, 0) - Vector3.UP * LevelData.ELEVATION_STEP
	var front_screen := camera.unproject_position(front_base)
	var picked_front: Vector2i = plugin._pick(camera, front_screen)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = front_screen
	click.pressed = true
	plugin._forward_3d_gui_input(camera, click)
	click.pressed = false
	plugin._forward_3d_gui_input(camera, click)
	suite.check(picked_front == front and sparse_data.cell_exists(front)
		and not sparse_data.cell_exists(front + Vector2i(0, 1)),
		"2.5D ground brush places the front neighbor without skipping a cell")
	var back := anchor + Vector2i(0, -1)
	camera.position = sparse_data.world_center(anchor, 0) + Vector3(0, 8, -12)
	camera.look_at(sparse_data.world_layer_center(anchor, 0))
	var back_screen := camera.unproject_position(
		sparse_data.world_layer_center(anchor, 0) + Vector3.FORWARD)
	var picked_back: Vector2i = plugin._pick(camera, back_screen)
	click.position = back_screen
	click.pressed = true
	plugin._forward_3d_gui_input(camera, click)
	click.pressed = false
	plugin._forward_3d_gui_input(camera, click)
	suite.check(picked_back == anchor and sparse_data.cell_exists(back)
		and not sparse_data.cell_exists(back + Vector2i(0, -1)),
		"reverse view attaches to the far face without skipping a cell")
	plugin.mode_select.selected = 0
	plugin.builder = real_builder
	plugin.data = real_data
	plugin._make_preview()
	viewport.queue_free()
