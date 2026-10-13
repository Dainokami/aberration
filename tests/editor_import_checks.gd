@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var importer = plugin.world_tools.tabs.get_child(2).get_child(0)
	suite.check(importer.generate_button.text == "生成物件",
		"import action has concise label without step number")
	suite.check(not importer.advanced.visible,
		"advanced explanations are not shown by default")
	var id := "test_import_" + ObjectRules.new_id()
	importer.generate_as.selected = 1
	importer._on_generate_as_changed(1)
	importer._accept_source("res://assets/source_art/ground_tree_pack_01/decal_marsh.png")
	importer.fields["id"].text = id
	importer.fields["name"].text = "导入测试"
	importer.tile_color_picker.color = Color("#335544")
	importer._refresh_preview()
	var hidden := true
	for control: Control in importer.object_controls:
		hidden = hidden and not control.visible
	suite.check(hidden and importer.tile_section.visible and not importer.advanced.visible,
		"tile import hides all object-only controls")
	suite.check(importer.preview_root.get_child(0) is MeshInstance3D and
		importer.preview_root.get_child(1).material_override is ShaderMaterial,
		"transparent tile preview composites base color")
	# Same button handler as the UI, not direct _generate_tile.
	importer._generate()
	var path := "res://data/tiles/" + id + ".tres"
	var tile := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TileDefinition
	suite.check(tile != null and tile.base_color == Color("#335544"),
		"generate button in tile mode creates TileDefinition")
	suite.check(not DirAccess.dir_exists_absolute("res://assets/generated/" + id),
		"tile generation never creates an object")
	var hash := FileAccess.get_sha256(path)
	importer.tile_color_picker.color = Color.RED
	importer._generate()
	suite.check(FileAccess.get_sha256(path) == hash, "duplicate tile generation changes no existing resource")
	var builtin_path := "res://data/tiles/grass.tres"
	var builtin_hash := FileAccess.get_sha256(builtin_path)
	importer.fields["id"].text = "grass"
	importer._generate()
	suite.check(FileAccess.get_sha256(builtin_path) == builtin_hash, "builtin tile IDs protected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	TileRegistry.invalidate()
	plugin.refresh_tile_list()
	importer.generate_as.selected = 0
	importer._on_generate_as_changed(0)
	importer._accept_source("res://assets/source_art/ground_tree_pack_01/tree_olive.png")
	suite.check(importer.analysis["pixels"] == Vector2i(1024, 1536) and
		not importer.blocking.button_pressed and importer.fields["foreground"].text.is_empty(),
		"new source recalculates dimensions and clears stale collision/layers")
	importer.fields["id"].text = id
	importer._generate()
	var directory := "res://assets/generated/" + id
	var object := load(directory.path_join("definition.tres")) as PlaceableDefinition
	suite.check(object != null and object.image_size.y > object.image_size.x,
		"generate button in object mode creates correct proportional object")
	for file in ["asset.tscn", "definition.tres", "thumbnail.png"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	plugin.world_tools.refresh_library()

func capture_panel(plugin: EditorPlugin) -> void:
	var importer = plugin.world_tools.tabs.get_child(2).get_child(0)
	var original_parent: Node = importer.get_parent()
	original_parent.remove_child(importer)
	var window := Window.new()
	window.title = "导入面板检查"
	window.size = Vector2i(760, 1600)
	plugin.get_tree().root.add_child(window)
	var background := ColorRect.new()
	background.color = Color("#25272c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	window.add_child(margin)
	margin.add_child(importer)
	importer.theme = EditorInterface.get_editor_theme()
	importer._accept_source("res://assets/source_art/ground_tree_pack_01/tree_olive.png")
	for i in 8:
		await plugin.get_tree().process_frame
	await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png("/tmp/import_panel_review.png")
	margin.remove_child(importer)
	original_parent.add_child(importer)
	window.queue_free()
