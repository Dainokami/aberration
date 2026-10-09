@tool
extends RefCounted

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print("EDITOR V2 CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var host := TerrainBuilder.new()
	host.level_data = LevelData.new()
	host.level_data.restore_data((load("res://data/levels/objects_acceptance.tres") as LevelData).clone_data())
	tree.root.add_child(host)
	plugin._edit(host)
	var initial: Dictionary = plugin.data.clone_data()
	var changed: Dictionary = initial.duplicate(true)
	changed["objects"].remove_at(0)
	plugin._commit_external(initial, changed, "V2自动检查：删除")
	check(plugin.data.objects.size() == 11, "commit object deletion")
	var manager := plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(plugin.data))
	history.undo()
	check(plugin.data.clone_data() == initial, "EditorUndoRedo restores full map")
	history.redo()
	check(plugin.data.objects.size() == 11, "EditorUndoRedo redoes deletion")
	history.undo()
	plugin.world_tools.selected_id = plugin.data.objects[0]["id"]
	plugin.world_tools.yaw_input.value = 90
	plugin.world_tools.apply_transform()
	check(is_equal_approx(plugin.data.objects[0]["yaw"], PI * 0.5), "object transform action")
	history.undo()
	check(plugin.data.clone_data() == initial, "transform undo")
	var old_map: LevelData = plugin.data
	var other := LevelData.new()
	other.setup_blank()
	plugin.data = other
	host.level_data = other
	history.redo()
	check(other.objects.is_empty() and old_map.objects.size() == 12, "undo history never edits another map")
	plugin.data = old_map
	host.level_data = old_map
	history.undo()
	plugin.current_path = "res://missing_directory_for_save_test/map.tres"
	plugin.dirty = true
	check(not plugin._save_map() and plugin.dirty and plugin.data.clone_data() == initial, "save failure retains data and dirty state")
	plugin.pending_action = "new"
	plugin.confirm_dialog.canceled.emit()
	check(plugin.pending_action.is_empty() and plugin.data == old_map, "cancel switch retains map")
	# Importer widgets and live preview exercise the same code used by the Dock.
	var importer = plugin.world_tools.tabs.get_child(1).get_child(0)
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
	plugin.world_tools.prefab = load("res://data/prefabs/demo_camp.tres")
	plugin.world_tools.prefab_mode.selected = 1
	plugin.world_tools._preview_prefab(Vector2i(3, 9))
	check(is_instance_valid(plugin.world_tools.ghost), "prefab preview builds")
	plugin.world_tools.reset()
	plugin.builder = null
	plugin.data = null
	host.queue_free()
	await tree.process_frame
	print("EDITOR V2 TEST FAILURES: ", failures)
	tree.quit(0 if failures.is_empty() else 1)
