@tool
extends RefCounted

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print("WORLDGEN EDITOR CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	if "--worldgen-interactive" in OS.get_cmdline_user_args():
		await plugin._open_editor_workspace()
		plugin._open_world_generation()
		return
	var host := TerrainBuilder.new()
	var original := LevelData.new()
	original.setup_blank(Vector2i(16, 16))
	original.set_layer(Vector2i(4, 4), 0, {"tile_id": "grass"})
	host.level_data = original
	tree.root.add_child(host)
	plugin._edit(host)
	plugin.current_path = "res://data/levels/unsaved_test_source.tres"
	plugin._set_dirty(true)
	plugin._open_world_generation()
	var dialog = plugin.world_gen_dialog
	dialog.config.width = 32
	dialog.config.height = 32
	dialog.config.spawn_radius = 3
	dialog.config.resource_density = 0
	dialog.config.environment_density = 0
	dialog.config.prefabs.assign([{"path": "res://data/prefabs/demo_camp.tres",
		"minimum": 1, "maximum": 1, "weight": 1, "zone": "any", "rotate": true}])
	dialog._sync()
	dialog._start()
	while dialog._thread != null:
		await tree.process_frame
	check(dialog.result != null and not dialog._apply.disabled, "dialog worker finishes with applicable preview")
	if dialog.result == null:
		print(dialog._status.text)
		tree.quit(1)
		return
	var generated: LevelData = dialog.result
	check(dialog._preview.data == generated, "preview displays generated data")
	dialog._mode.select(1)
	dialog._mode.item_selected.emit(1)
	check(dialog._preview.mode == 1, "zone view selection works")
	plugin.world_gen_target = null
	dialog._apply_result()
	check(dialog.visible and not dialog._apply.disabled and plugin.data == original,
		"rejected application keeps the preview and does not claim success")
	plugin.world_gen_target = host
	dialog._apply_result()
	check(plugin.data == generated and host.level_data == generated
		and plugin.current_path == "" and plugin.dirty, "apply creates new unsaved map")
	check(host._chunk_nodes.size() > 0, "apply renders actual 3D terrain")
	var history_id := plugin.get_undo_redo().get_object_history_id(host)
	var history := plugin.get_undo_redo().get_history_undo_redo(history_id)
	history.undo()
	check(host.level_data == original and plugin.data == original and plugin.dirty
		and plugin.current_path == "res://data/levels/unsaved_test_source.tres",
		"real editor undo restores original map and save path")
	history.redo()
	check(host.level_data == generated and plugin.current_path == "", "real editor redo restores generated map")
	plugin.current_path = "res://data/levels/world_test_saved.tres"
	plugin._set_dirty(false)
	history.undo()
	history.redo()
	check(plugin.current_path == "res://data/levels/world_test_saved.tres" and not plugin.dirty,
		"undo redo preserves later save path")
	var unrelated := LevelData.new()
	unrelated.setup_blank()
	host.level_data = unrelated
	plugin.data = unrelated
	history.undo()
	check(host.level_data == unrelated, "stale undo cannot replace an unrelated opened map")
	dialog._inputs.width.value = 48
	check(dialog._apply.disabled, "parameter edits invalidate previous result")
	dialog._file_action = "save"
	dialog._file_selected("/tmp/aberration-worldgen-recipe.tres")
	dialog.config.seed_value = 7
	dialog._file_action = "load"
	dialog._file_selected("/tmp/aberration-worldgen-recipe.tres")
	check(dialog.config.width == 48 and dialog.config.seed_value == 20261018,
		"recipe save and load retain parameter values and sources")
	dialog._inputs.width.value = 600
	dialog._inputs.height.value = 600
	dialog._start()
	dialog._cancel_generation()
	while dialog._thread != null:
		await tree.process_frame
	check(dialog._apply.disabled and dialog._status.text == "已取消", "worker cancellation leaves apply disabled")
	dialog.hide()
	plugin._disable_2_5d_view()
	plugin.builder = null
	plugin.data = null
	host.queue_free()
	await tree.process_frame
	print("WORLDGEN EDITOR FAILURES ", failures)
	tree.quit(0 if failures.is_empty() else 1)
