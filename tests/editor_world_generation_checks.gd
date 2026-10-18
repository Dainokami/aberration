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
		if "--worldgen-showcase" in OS.get_cmdline_user_args():
			var dialog = plugin.world_gen_dialog
			dialog.config = load("res://data/worldgen_three_landmarks_recipe.tres").duplicate(true)
			dialog._sync()
			dialog._tabs.current_tab = 2
			dialog.map_ready.connect(func(data: LevelData):
				_show_aligned_world.call_deferred(plugin, data))
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
	var blend: CheckBox = dialog._source_rows.find_child("BlendEdges", true, false)
	check(blend != null and blend.button_pressed, "source rule defaults to exterior blending")
	blend.button_pressed = false
	check(dialog._apply.disabled and not dialog.config.prefabs[0].blend_edges,
		"blend toggle updates the rule and invalidates the old preview")
	blend.button_pressed = true
	var alignment: CheckBox = dialog._source_rows.find_child("AlignHeight", true, false)
	check(alignment != null and alignment.button_pressed, "source ground alignment defaults on")
	alignment.button_pressed = false
	check(dialog._apply.disabled and not dialog.config.prefabs[0].align_height,
		"height toggle updates the rule and invalidates the old preview")
	alignment.button_pressed = true
	dialog._start()
	while dialog._thread != null:
		await tree.process_frame
	generated = dialog.result
	plugin.world_gen_target = host
	dialog._apply_result()
	check(plugin.data == generated and host.level_data == generated
		and plugin.current_path == "" and plugin.dirty, "apply creates new unsaved map")
	check(host._chunk_nodes.size() > 0, "apply renders actual 3D terrain")
	var placement: Dictionary = generated.generation.placements[0]
	check(placement.layer == 1 and generated.top_layer(placement.entry) == 1,
		"applied special-map entrance is level with the generated world")
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
	blend.button_pressed = false
	alignment.button_pressed = false
	dialog._file_action = "save"
	dialog._file_selected("/tmp/aberration-worldgen-recipe.tres")
	dialog.config.seed_value = 7
	dialog._file_action = "load"
	dialog._file_selected("/tmp/aberration-worldgen-recipe.tres")
	check(dialog.config.width == 48 and dialog.config.seed_value == 20261018,
		"recipe save and load retain parameter values and sources")
	check(not dialog.config.prefabs[0].blend_edges
		and not dialog._source_rows.find_child("BlendEdges", true, false).button_pressed,
		"recipe roundtrip preserves the blending opt-out and checkbox")
	check(not dialog.config.prefabs[0].align_height
		and not dialog._source_rows.find_child("AlignHeight", true, false).button_pressed,
		"recipe roundtrip preserves height-alignment opt-out and checkbox")
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

## Fits the camera and saves only after the user actually applies through the UI.
func _show_aligned_world(plugin: EditorPlugin, data: LevelData) -> void:
	if plugin.data != data:
		return
	var path := "res://data/levels/generated_special_world_aligned.tres"
	check(ResourceSaver.save(data, path) == OK, "interactive applied world saved as new resource")
	for placement in data.generation.placements:
		check(data.top_layer(placement.entry) == data.top_layer(placement.outside),
			"interactive world entrance matches surrounding terrain: " + placement.name)
		if str(placement.source).contains("grass_plateau"):
			var center: Vector2i = placement.rect.position + placement.rect.size / 2
			plugin.view_pan_offset = data.world_center(center) * Vector3(1, 0, 1)
			plugin.preview_distance = 58
			plugin.preview_pitch = 45
			plugin.preview_target_height = 4
			plugin._enable_2_5d_view()
	plugin._set_status("高度检查：特殊地形基准地面与世界均为第1层，顶面4m；内部高台为6m")
