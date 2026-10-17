@tool
extends RefCounted

## Renders real dock pages in a narrow window with the editor theme.
## Run: Godot --path . --editor -- --test-v2-editor --capture-art-panels
## Only captures (no test suite); images go to /tmp/aberration-panel-*.png.
const WIDTH := 360

func run(plugin: EditorPlugin) -> void:
	var tabs: TabContainer = plugin.world_tools.tabs
	var dock = tabs.get_child(2).get_child(0)
	var panel = dock.scene_panel
	var root := "res://assets/derived_art/scene_pack_20261014/"
	dock.generate_as.selected = 2
	dock._on_generate_as_changed(2)
	dock._accept_source(root + "terrain/grass.png")
	panel.accept_slot("cliff", root + "terrain/cliff_body.png")
	panel.accept_slot("rim", root + "terrain/rim_grass.png")
	panel.accept_slot("slope", root + "terrain/slope.png")
	panel.cliff_span.value = 6.4453
	panel.cliff_height.value = 1.0078
	panel.rim_span.value = 6.4453
	panel.rim_rise.value = 0.2344
	panel.rim_drop.value = 0.5
	await _capture(plugin, tabs.get_child(2), "import-terrain", 1500)
	dock.generate_as.selected = 4
	dock._on_generate_as_changed(4)
	dock._accept_source(root + "objects/rock_frontface.png")
	for face in ["left", "right", "top"]:
		panel.accept_slot(face, root + "objects/rock_sideface.png")
	panel.tools.visible = true
	await _capture(plugin, tabs.get_child(2), "import-rock", 1700)
	panel.tools.visible = false
	dock.generate_as.selected = 5
	dock._on_generate_as_changed(5)
	dock._accept_source(root + "objects/treasurebox.png")
	panel.accept_slot("open", root + "objects/treasurebox_open.png")
	await _capture(plugin, tabs.get_child(2), "import-chest", 1300)
	dock.generate_as.selected = 0
	dock._on_generate_as_changed(0)
	var details = plugin.world_tools.detail_tools
	details.mode.selected = 1
	details.scatter_source.selected = 1
	details.advanced.button_pressed = true
	details.parameters.visible = true
	details.advanced.text = "▾ 更多设置"
	await _capture(plugin, tabs.get_child(5), "details-single", 1450)
	details.advanced.button_pressed = false
	details.parameters.visible = false
	details.advanced.text = "▸ 更多设置"
	details.scatter_source.selected = 0
	await _capture(plugin, tabs.get_child(5), "details-mixed", 800)
	var prefab = plugin.world_tools
	prefab.prefab_mode.selected = 0
	await _capture(plugin, tabs.get_child(3), "prefab-create", 900)
	prefab.prefab_mode.selected = 1
	await _capture(plugin, tabs.get_child(3), "prefab-use", 1200)

func _capture(plugin: EditorPlugin, page: Control, suffix: String, height: int) -> void:
	var parent := page.get_parent()
	var index := page.get_index()
	var was_visible := page.visible
	var scale := EditorInterface.get_editor_scale()
	parent.remove_child(page)
	var window := Window.new()
	window.title = "Dock review"
	window.size = Vector2i(int(WIDTH * scale), int(height * scale))
	window.theme = EditorInterface.get_editor_theme()
	plugin.get_tree().root.add_child(window)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(background)
	window.add_child(page)
	page.visible = true
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Grow the page to its content so the whole form is visible in one image.
	var content := page.get_child(0) as Control if page is ScrollContainer else page
	for i in 6:
		await plugin.get_tree().process_frame
	window.size = Vector2i(int(WIDTH * scale), maxi(int(height * scale),
		int(content.get_combined_minimum_size().y) + 24))
	for i in 6:
		await plugin.get_tree().process_frame
	# frame_post_draw is unreliable for an extra OS window; read the texture directly.
	var path := "/tmp/aberration-panel-%s.png" % suffix
	var error := window.get_texture().get_image().save_png(path)
	print("PANEL CAPTURE ", path, " ", error_string(error), " min_width=",
		content.get_combined_minimum_size().x / scale)
	window.remove_child(page)
	parent.add_child(page)
	parent.move_child(page, index)
	page.visible = was_visible
	window.queue_free()
