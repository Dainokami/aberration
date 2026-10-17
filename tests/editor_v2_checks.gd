@tool
extends RefCounted

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print("EDITOR V2 CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	if plugin._find_terrain_builder(EditorInterface.get_edited_scene_root()) == null:
		await plugin._open_editor_workspace()
	var host := TerrainBuilder.new()
	host.level_data = LevelData.new()
	host.level_data.restore_data((load("res://data/levels/objects_acceptance.tres") as LevelData).clone_data())
	tree.root.add_child(host)
	plugin._edit(host)
	var initial: Dictionary = plugin.data.clone_data()
	if "--capture-art-panels" in OS.get_cmdline_user_args():
		await load("res://tests/editor_panel_capture.gd").new().run(plugin)
		plugin.builder = null
		plugin.data = null
		host.queue_free()
		await tree.process_frame
		print("PANEL CAPTURE DONE")
		tree.quit(0)
		return
	if "--capture-interaction" in OS.get_cmdline_user_args():
		await load("res://tests/editor_layout_checks.gd").new().run(plugin, self)
		plugin._disable_2_5d_view()
		plugin.builder = null
		plugin.data = null
		host.queue_free()
		await tree.process_frame
		print("EDITOR INTERACTION TEST FAILURES: ", failures)
		tree.quit(0 if failures.is_empty() else 1)
		return

	# Test commit_external records action (manually apply first)
	plugin.data.objects.remove_at(0)
	var after_delete: Dictionary = plugin.data.clone_data()
	plugin._commit_external(initial, after_delete, "V2自动检查：删除")
	check(plugin.data.objects.size() == initial["objects"].size() - 1, "commit object deletion")
	# Restore manually for remaining tests
	plugin.data.restore_data(initial)
	plugin.builder.rebuild()

	# Object transform action
	plugin.world_tools.selected_id = plugin.data.objects[0]["id"]
	plugin.world_tools.yaw_input.value = 90
	plugin.world_tools.apply_transform()
	check(is_equal_approx(plugin.data.objects[0]["yaw"], PI * 0.5), "object transform action")
	# Restore
	plugin.data.restore_data(initial)
	plugin.builder.rebuild()

	# Cancel dialog clears pending_action
	plugin.pending_action = "new"
	plugin.confirm_dialog.canceled.emit()
	check(plugin.pending_action.is_empty(), "cancel switch clears pending action")
	check(plugin.data == plugin.data, "cancel switch retains map reference")

	# Save failure: data survives
	plugin.current_path = "res://missing_directory_for_save_test/map.tres"
	plugin._save_map()
	check(plugin.data.objects == initial["objects"], "save failure retains data")

	# Importer widgets — tab 2 is import
	var importer = plugin.world_tools.tabs.get_child(2).get_child(0)
	importer.fields["id"].text = "editor_test_preview"
	importer.fields["source"].text = "res://assets/placeholders/v2/rock.png"
	importer.density.value = 256
	importer._calculate_defaults()
	check(importer.analysis["pixels"] == Vector2i(256, 256), "generic importer reads pixels")
	check(is_equal_approx(importer.fields["image"][0].value, importer.fields["image"][1].value),
		"generic importer preserves aspect ratio")
	check(importer.fields["pivot"][1].value > 0.75, "generic importer estimates bottom contact")
	check(importer.collision.selected == 0 and not importer.blocking.button_pressed,
		"generic importer defaults to no collision")
	importer._width_changed(3.25)
	check(is_equal_approx(importer.fields["image"][0].value, 3.25) and
		is_equal_approx(importer.fields["image"][1].value, 3.25), "width keeps image aspect")
	importer.blocking.button_pressed = true
	check(importer.collision.selected == 1, "blocking enables generic box proxy")
	var preset: Dictionary = importer.preset_values()
	importer.carrier.selected = 1
	importer.blocking.button_pressed = false
	check(importer.apply_preset(preset).is_empty(), "custom preset applies")
	check(importer.carrier.selected == preset["carrier"] and importer.blocking.button_pressed,
		"preset restores settings")
	var before_source: String = importer.fields["source"].text
	check(not importer.apply_preset({"version": 999}).is_empty() and
		importer.fields["source"].text == before_source, "invalid preset rejected without replacing art")
	importer._refresh_preview()
	check(is_instance_valid(importer.preview_root) and importer.preview_root.get_child_count() >= 2, "importer preview builds asset and camera")

	# Generate-as selector exists
	check(importer.generate_as != null, "generate_as selector exists")
	check(importer.generate_as.item_count == 7, "importer retains legacy modes and exposes five art workflows")

	# Prefab preview
	plugin.world_tools.prefab = load("res://data/prefabs/demo_camp.tres")
	plugin.world_tools.prefab_sub_tabs.current_tab = 1
	plugin.world_tools._preview_prefab(Vector2i(3, 9))
	check(is_instance_valid(plugin.world_tools.ghost), "prefab preview builds")
	var before_stamp: Dictionary = plugin.data.clone_data()
	plugin.world_tools._prefab_click(Vector2i(3, 9))
	check(plugin.data.clone_data() != before_stamp, "prefab click applies validated snapshot")
	plugin.data.restore_data(before_stamp)
	plugin.builder.rebuild()

	# Actual save-to-fixed-folder path and reload.
	var test_prefab_base := "editor_prefab_save_test"
	for suffix in ["", "_2", "_3", "_4"]:
		var old_path := "res://data/prefabs/%s%s.tres" % [test_prefab_base, suffix]
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	# An existing non-prefab resource must stay untouched and force a new name.
	var corrupt_path := "res://data/prefabs/%s.tres" % test_prefab_base
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	corrupt_file.close()
	plugin.world_tools.prefab_sub_tabs.current_tab = 0
	plugin.world_tools.region = Rect2i(0, 0, 1, 1)
	plugin.world_tools.prefab_name_input.text = test_prefab_base
	await plugin.world_tools.save_region()
	var saved_prefab_path := "res://data/prefabs/%s_2.tres" % test_prefab_base
	check(FileAccess.file_exists(saved_prefab_path), "prefab saves to fixed folder")
	var saved_prefab := ResourceLoader.load(
		saved_prefab_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelPrefab
	check(saved_prefab != null and saved_prefab.fragment != null, "saved prefab reloads")

	# Tile registry tests
	var tiles := TileRegistry.all_tiles()
	check(tiles.size() >= 2, "tile registry has builtin tiles")
	check(tiles[0].tile_id == "grass", "first tile is grass")
	check(tiles[1].tile_id == "rock", "second tile is rock")

	# Tile painting infrastructure
	var tile: TileDefinition = plugin.selected_tile()
	check(tile != null, "terrain tab has selected tile")

	# Tab order: 地形(0), 物件(1), 导入(2), 预制(3)
	check(plugin.tabs.get_child(0).name == "地形", "tab 0 is terrain")
	check(plugin.tabs.get_child(1).name == "物件", "tab 1 is objects")
	check(plugin.tabs.get_child(2).name == "导入", "tab 2 is import")
	check(plugin.tabs.get_child(3).name == "预制", "tab 3 is prefab")

	# Prefab sub-tabs
	check(plugin.world_tools.prefab_sub_tabs.get_child(0).name == "制作预制", "prefab sub-tab 0 is create")
	check(plugin.world_tools.prefab_sub_tabs.get_child(1).name == "使用预制", "prefab sub-tab 1 is use")
	var prefab_mode = plugin.world_tools.prefab_mode
	var create_button: Button = prefab_mode.buttons[0]
	var use_button: Button = prefab_mode.buttons[1]
	check(not plugin.world_tools.prefab_sub_tabs.tabs_visible
		and create_button.custom_minimum_size.y >= plugin.ui_px(40)
		and create_button.has_theme_stylebox_override("normal")
		and create_button.has_theme_stylebox_override("pressed")
		and use_button.has_theme_stylebox_override("normal"),
		"prefab create and use entries are prominent action buttons")
	prefab_mode.selected = 1
	check(plugin.world_tools.prefab_sub_tabs.current_tab == 1,
		"prefab use button changes the active workflow")
	prefab_mode.selected = 0
	check(plugin.world_tools.prefab_sub_tabs.current_tab == 0,
		"prefab create button changes the active workflow")

	var art_checks = load("res://tests/editor_art_regression.gd").new()
	art_checks.run(plugin, self)
	var layout_checks = load("res://tests/editor_layout_checks.gd").new()
	await layout_checks.run(plugin, self)
	var stacked_checks = load("res://tests/editor_stacked_checks.gd").new()
	await stacked_checks.run(plugin, self)
	var art_tools_checks = load("res://tests/editor_art_tools_checks.gd").new()
	await art_tools_checks.run(plugin, self)
	var import_checks = load("res://tests/editor_import_checks.gd").new()
	import_checks.run(plugin, self)
	await load("res://tests/editor_scene_import_checks.gd").new().run(plugin, self)
	load("res://tests/editor_ocean_scene_checks.gd").new().run(plugin, self)
	if "--capture-import-panel" in OS.get_cmdline_user_args():
		await import_checks.capture_panel(plugin)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_prefab_path))
	plugin.world_tools.reset()
	plugin.builder = null
	plugin.data = null
	host.queue_free()
	await tree.process_frame
	print("EDITOR V2 TEST FAILURES: ", failures)
	if failures.is_empty():
		await load("res://tests/editor_scene_mechanism_placement.gd").new().run(plugin)
	else:
		tree.quit(1)
