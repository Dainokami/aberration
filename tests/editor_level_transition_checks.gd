@tool
extends RefCounted

var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	print("PORTAL EDITOR CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func flat_map() -> LevelData:
	var map := LevelData.new()
	map.setup_blank(Vector2i(8, 8))
	for i in map.columns.size():
		map.columns[i] = {"layers": [{"tile_id": "grass"}]}
	map.spawn_cell = Vector2i(4, 4)
	map.spawn_layer = 0
	return map

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	plugin._disable_2_5d_view()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	tree.root.add_child(viewport)
	var map := flat_map()
	var builder := TerrainBuilder.new()
	builder.level_data = map
	viewport.add_child(builder)
	plugin._edit(builder)
	var tools = plugin.transition_tools
	plugin.tabs.current_tab = tools.page.get_parent().get_index()
	check(plugin.tabs.get_current_tab_control().name == "流程", "dedicated flow tab")
	check(map.level_transition == null and tools.controls.enabled.button_pressed \
		and tools.controls.countdown_seconds.value == 60, "legacy defaults displayed without writing")
	tools.controls.countdown_seconds.value = 5
	check(map.level_transition != null and map.level_transition.countdown_seconds == 5 \
		and plugin.dirty, "real SpinBox edits config and marks map dirty")
	var history := plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	history.undo()
	check(map.level_transition == null and tools.controls.countdown_seconds.value == 60,
		"native undo restores absent field and controls")
	history.redo()
	check(map.level_transition.countdown_seconds == 5, "native redo restores settings")
	tools.controls.enabled.button_pressed = false
	check(not map.level_transition.enabled, "real enable toggle")
	history.undo()
	check(map.level_transition.enabled, "toggle undo")
	tools.controls.radius_min.value = 3
	tools.controls.radius_max.value = 7
	check(map.level_transition.radius_min == 3 and map.level_transition.radius_max == 7,
		"consecutive edits preserve both values")
	tools.controls.target_level.text = "res://data/levels/acceptance_map.tres"
	tools.controls.target_level.text_submitted.emit(tools.controls.target_level.text)
	check(map.level_transition.target_level.ends_with("acceptance_map.tres"),
		"submitted target path persists")
	history.undo()
	check(map.level_transition.target_level == LevelTransitionConfig.DEFAULT_TARGET, "target undo")
	tools.dialog_target = map
	tools.target_dialog.file_selected.emit("res://data/levels/art_acceptance.tres")
	check(map.level_transition.target_level.ends_with("art_acceptance.tres"), "file chooser applies LevelData")
	tools.target_dialog.file_selected.emit("res://data/art_profile.tres")
	check(map.level_transition.target_level.ends_with("art_acceptance.tres"), "file chooser rejects other resources")
	tools.controls.target_level.text = LevelTransitionConfig.DEFAULT_TARGET
	tools.controls.target_level.focus_exited.emit()
	check(map.level_transition.target_level == LevelTransitionConfig.DEFAULT_TARGET, "focus exit commits path")
	tools.validate_button.pressed.emit()
	check(plugin.status.text.contains("传送配置有效"), "validate button gives feedback")
	var path := "/tmp/aberration-portal-editor-roundtrip.tres"
	check(ResourceSaver.save(map, path) == OK, "save map from editor")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.level_transition.snapshot() == map.level_transition.snapshot(), "reload preserves all flow values")
	var generated := flat_map()
	plugin.world_gen_target = builder
	plugin._apply_generated_world(generated)
	check(generated.level_transition != null \
		and generated.level_transition.snapshot() == map.level_transition.snapshot() \
		and generated.level_transition != map.level_transition, "generation inherits independent flow config")
	var builder_history := plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(builder))
	builder_history.undo()
	check(plugin.data == map, "generation undo returns original map")
	builder_history.redo()
	check(plugin.data == generated, "generation redo restores generated flow")
	await tree.process_frame
	check(tools.observed_data == generated, "flow panel follows generation replacement")
	var other := flat_map()
	builder.level_data = other
	plugin._edit(builder)
	tools.dialog_target = map
	tools.target_dialog.file_selected.emit(LevelTransitionConfig.DEFAULT_TARGET)
	check(other.level_transition == null, "stale chooser cannot edit another map")
	history.undo()
	check(other.level_transition == null and tools.controls.countdown_seconds.value == 60,
		"old undo cannot write current map or stale panel")
	if "--portal-editor-capture" in OS.get_cmdline_user_args():
		plugin.editor_dock.make_visible()
		plugin.tabs.current_tab = tools.page.get_parent().get_index()
		for i in 5:
			await tree.process_frame
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("/tmp/portal-editor-settings.png")
	plugin._edit(null)
	check(tools.choose_button.disabled and not tools.controls.countdown_seconds.editable,
		"no active map disables editing")
	viewport.queue_free()
	await tree.process_frame
	print("PORTAL EDITOR CHECKS ", checks, " FAILURES ", failures)
	if "--portal-editor-interactive" in OS.get_cmdline_user_args() and failures.is_empty():
		await plugin._open_editor_workspace()
		plugin.tabs.current_tab = tools.page.get_parent().get_index()
		print("PORTAL EDITOR INTERACTIVE READY")
		return
	tree.quit(0 if failures.is_empty() else 1)
