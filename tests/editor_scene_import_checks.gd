@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var dock = plugin.world_tools.tabs.get_child(2).get_child(0)
	var panel = dock.scene_panel
	var id := "scene_import_test_" + ObjectRules.new_id().left(8)
	var source := "res://assets/placeholders/v2/rock.png"
	var digest := FileAccess.get_sha256(source)
	dock.generate_as.selected = 3
	dock._on_generate_as_changed(3)
	dock._accept_source(source)
	panel.accept_slot("variant_1", source)
	var frames := [0]
	var count := func(): frames[0] += 1
	plugin.get_tree().process_frame.connect(count)
	await panel.process_images()
	plugin.get_tree().process_frame.disconnect(count)
	suite.check(not panel.busy and panel.applied and frames[0] > 1,
		"native image processing yields editor frames and imports derived images")
	suite.check(FileAccess.get_sha256(source) == digest and not panel.manifest_path.is_empty(),
		"image processing preserves source hash and saves recipe")
	var atlas_import := ConfigFile.new()
	var atlas_path := str(panel.atlas_result.get("path", ""))
	var atlas_loaded := atlas_import.load(atlas_path + ".import")
	var atlas_texture := ResourceLoader.load(atlas_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	suite.check(atlas_loaded == OK and atlas_import.has_section_key("remap", "uid")
		and atlas_import.get_value("params", "mipmaps/generate", false) == true
		and atlas_import.get_value("params", "detect_3d/compress_to", 1) == 0
		and atlas_texture != null and atlas_texture.get_image().has_mipmaps(),
		"processed art imports with mipmaps and no 3D auto-detect reimport")
	dock.fields["id"].text = id
	dock.fields["name"].text = "图集流程测试"
	dock._generate()
	var detail_path := "res://data/details/" + id + ".tres"
	var detail := load(detail_path) as DetailSet
	suite.check(detail != null and detail.variants.size() == 2 and detail.validate_asset().is_empty(),
		"detail importer writes two valid atlas variants")
	dock._refresh_preview()
	suite.check(dock.preview_root.get_child(0) is MultiMeshInstance3D,
		"detail preview uses actual atlas material and instance transforms")
	var hash := FileAccess.get_sha256(detail_path)
	dock._generate()
	suite.check(FileAccess.get_sha256(detail_path) == hash, "duplicate detail ID remains unchanged")
	var derived: String = panel.manifest_path.get_base_dir()
	DirAccess.remove_absolute(detail_path)
	for file in DirAccess.get_files_at(derived):
		DirAccess.remove_absolute(derived.path_join(file))
	DirAccess.remove_absolute(derived)
	dock.generate_as.selected = 2
	dock._on_generate_as_changed(2)
	dock._accept_source("res://assets/derived_art/scene_pack_20261014/terrain/grass.png")
	panel.accept_slot("cliff", "res://assets/derived_art/scene_pack_20261014/terrain/cliff.png")
	panel.accept_slot("slope", "res://assets/derived_art/scene_pack_20261014/terrain/slope.png")
	dock.fields["id"].text = id
	dock._generate()
	var tile_path := "res://data/tiles/" + id + ".tres"
	var tile := load(tile_path) as TileDefinition
	suite.check(tile != null and tile.art_set != null and tile.world_space_top
		and tile.art_set.slope_side_path.ends_with("slope.png"),
		"terrain importer creates linked continuous kit and tile")
	DirAccess.remove_absolute(tile_path)
	DirAccess.remove_absolute("res://data/terrain_art/" + id + ".tres")
	TileRegistry.invalidate()
	dock.generate_as.selected = 4
	dock._on_generate_as_changed(4)
	dock._accept_source("res://assets/derived_art/scene_pack_20261014/objects/rock_frontface.png")
	for face in ["left", "right", "top"]:
		panel.accept_slot(face, "res://assets/derived_art/scene_pack_20261014/objects/rock_topface2.png")
	panel.behaviour.selected = PlaceableDefinition.Behaviour.BREAKABLE
	dock.fields["id"].text = id
	var definition: PlaceableDefinition = dock.make_definition()
	suite.check(definition.validate_asset().is_empty() and definition.supports_objects
		and definition.behaviour == PlaceableDefinition.Behaviour.BREAKABLE,
		"multi-face import combines explicit slots collision support and gameplay")
	dock._generate()
	var folder := "res://assets/generated/" + id
	var saved := load(folder.path_join("definition.tres")) as PlaceableDefinition
	var instance := AssetFactory.instantiate_asset(saved) if saved != null else null
	suite.check(instance != null and instance.has_method("apply_damage"),
		"multi-face generated scene retains gameplay behaviour")
	if instance != null:
		instance.free()
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)
	# Logical width: a HiDPI editor (scale 2) doubles every control's pixels.
	var scale := EditorInterface.get_editor_scale()
	for mode in range(7):
		dock.generate_as.selected = mode
		dock._on_generate_as_changed(mode)
		await plugin.get_tree().process_frame
		var width: float = dock.get_combined_minimum_size().x / scale
		print("ART IMPORT MODE %d min width %.0f (editor scale %.2f)" % [mode, width, scale])
		suite.check(width <= 380, "art import mode %d fits narrow dock" % mode)
	# Card grids scale with the editor: a standard 310px dock still shows three
	# readable detail cards per row instead of collapsing to one HiDPI column.
	var palette: ItemList = plugin.world_tools.detail_tools.palette
	var columns := floori((310.0 * scale) / float(palette.fixed_column_width))
	suite.check(columns >= 3 and palette.fixed_icon_size.x >= roundi(48 * scale),
		"detail cards keep three columns at editor scale %.2f" % scale)
	dock.generate_as.selected = 0
	dock._on_generate_as_changed(0)
	plugin.refresh_tile_list()
	plugin.world_tools.refresh_library()
	plugin.world_tools.detail_tools.refresh_library()
