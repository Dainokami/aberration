@tool
extends RefCounted

func run(plugin: EditorPlugin, suite: RefCounted) -> void:
	var original: LevelData = plugin.data
	var original_builder_data: LevelData = plugin.builder.level_data
	var selected: PackedInt32Array = plugin.tile_list.get_selected_items()
	var old_layer: int = plugin.active_layer
	var map := LevelData.new()
	map.setup_blank(Vector2i(4,4))
	plugin.data = map
	plugin.builder.level_data = map
	var tiles := TileRegistry.all_tiles()
	for index in tiles.size():
		if tiles[index].tile_id == "water":
			plugin.tile_list.select(index)
	plugin.active_layer = 0
	var cell := Vector2i(1,1)
	var blocks: Array[Vector3i] = [Vector3i(1,0,1)]
	var prepared: Dictionary = plugin._prepare_ground_blocks(blocks)
	suite.check(prepared.error.is_empty() and prepared.candidate.is_water_layer(cell,0)
		and not prepared.candidate.is_solid_layer(cell,0), "ocean brush on empty grid creates only water")
	plugin.builder.rebuild()
	var before := map.clone_data()
	plugin.touched.clear()
	plugin._paint_ground_blocks(blocks)
	plugin._commit_external(before,map.clone_data(),"Ocean standalone brush")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
		plugin.get_undo_redo().get_object_history_id(map))
	history.undo()
	suite.check(not map.layer_exists(cell,0), "water placement undo restores empty grid")
	history.redo()
	suite.check(map.is_water_layer(cell,0), "water placement redo restores water volume")
	plugin.active_layer = 1
	plugin._update_preview(cell)
	var preview := plugin.preview.get_child(0) as TerrainBuilder
	suite.check(not preview.build_collision and preview.level_data.is_water_layer(Vector2i.ZERO,1)
		and not preview.level_data.layer_exists(Vector2i.ZERO,0), "water preview contains no invented grass support")
	plugin.active_layer = 0
	plugin.touched.clear()
	plugin._erase_blocks(blocks)
	suite.check(not map.cell_exists(cell), "water erasure removes the entire independent block")
	plugin.data = original
	plugin.builder.level_data = original_builder_data
	plugin.builder.rebuild()
	plugin.active_layer = old_layer
	if not selected.is_empty():
		plugin.tile_list.select(selected[0])
