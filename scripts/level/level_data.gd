@tool
class_name LevelData
extends Resource

const CELL_SIZE := 2.0
const ELEVATION_STEP := 2.0
const BASE_Y := 0.0
const TERRAIN_GRASS := 0
const TERRAIN_ROCK := 1
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FORMAT_VERSION := 6
const MAX_MAP_SIZE := Vector2i(128, 128)
const MAX_LAYERS := 32
const DEFAULT_SOLID_TILE := "grass"

@export var map_size := Vector2i(16, 16)
## Minimum logical cell coordinate covered by the editable map bounds.
@export var map_origin := Vector2i.ZERO
## World-space corner of logical cell (0, 0), independent from map bounds.
@export var grid_world_origin := Vector2.ZERO
@export var has_grid_world_origin := false
## v6 source of truth. Each entry contains continuous solid `layers` plus
## optional `liquid` and `overlay` records attached to the highest solid layer.
@export var columns: Array[Dictionary] = []
## Legacy v5 payload. It is consumed and cleared by ensure_layout().
@export var cells: Array[Dictionary] = []
@export var stairs: Array[Dictionary] = []
@export var spawn_cell := Vector2i(-1, -1)
@export var spawn_layer := -1
@export var format_version := 5
@export var objects: Array[Dictionary] = []
## Per-map color overrides. Alpha is tint strength; RGB is the target hue.
@export var terrain_tints: Dictionary = {}

var _ensuring_layout := false

func setup_blank(size := Vector2i(16, 16)) -> void:
	map_size = size
	map_origin = Vector2i.ZERO
	grid_world_origin = -Vector2(size) * CELL_SIZE * 0.5
	has_grid_world_origin = true
	columns.clear()
	columns.resize(size.x * size.y)
	for i in columns.size():
		columns[i] = _blank_column()
	cells.clear()
	stairs.clear()
	objects.clear()
	terrain_tints.clear()
	spawn_cell = Vector2i(-1, -1)
	spawn_layer = -1
	format_version = FORMAT_VERSION

func ensure_layout() -> void:
	var wanted := map_size.x * map_size.y
	if _ensuring_layout:
		return
	if has_grid_world_origin and format_version >= FORMAT_VERSION \
			and cells.is_empty() and columns.size() == wanted:
		return
	_ensuring_layout = true
	if not has_grid_world_origin:
		grid_world_origin = -Vector2(map_size) * CELL_SIZE * 0.5
		has_grid_world_origin = true
	var legacy := not cells.is_empty() and (
		format_version < FORMAT_VERSION or columns.is_empty())
	if legacy:
		_migrate_legacy_cells(wanted)
	else:
		var old_size := columns.size()
		columns.resize(wanted)
		for i in wanted:
			if i >= old_size or not columns[i] is Dictionary:
				columns[i] = _blank_column()
			else:
				columns[i] = _normalized_column(columns[i])
		if format_version < FORMAT_VERSION:
			_migrate_anchors()
	cells.clear()
	format_version = FORMAT_VERSION
	_normalize_anchors()
	_ensuring_layout = false

func tile_id(cell: Vector2i, layer := -1) -> String:
	if layer >= 0:
		return str(get_layer(cell, layer).get("tile_id", DEFAULT_SOLID_TILE))
	var column := get_column(cell)
	if column.is_empty():
		return DEFAULT_SOLID_TILE
	var liquid: Dictionary = column.get("liquid", {})
	if not liquid.is_empty():
		return str(liquid.get("tile_id", "water"))
	var layers: Array = column.get("layers", [])
	if layers.is_empty():
		return DEFAULT_SOLID_TILE
	return str((layers[layers.size() - 1] as Dictionary).get(
		"tile_id", DEFAULT_SOLID_TILE))

func solid_tile_id(cell: Vector2i, layer := -1) -> String:
	var target := top_layer(cell) if layer < 0 else layer
	return str(get_layer(cell, target).get("tile_id", DEFAULT_SOLID_TILE))

func overlay_tile_id(cell: Vector2i) -> String:
	var overlay := get_attachment(cell, "overlay")
	return str(overlay.get("tile_id", ""))

func in_bounds(cell: Vector2i) -> bool:
	return map_bounds().has_point(cell)

func index(cell: Vector2i) -> int:
	var local := cell - map_origin
	return local.y * map_size.x + local.x

func map_bounds() -> Rect2i:
	return Rect2i(map_origin, map_size)

func map_world_origin() -> Vector2:
	ensure_layout()
	return grid_world_origin + Vector2(map_origin) * CELL_SIZE

func contains_region(region: Rect2i) -> bool:
	if region.size.x <= 0 or region.size.y <= 0:
		return true
	return in_bounds(region.position) and in_bounds(region.end - Vector2i.ONE)

func expansion_error(region: Rect2i, padding := 2) -> String:
	var expanded := _expanded_bounds(region, padding)
	if expanded.size.x > MAX_MAP_SIZE.x or expanded.size.y > MAX_MAP_SIZE.y:
		return "地图最大支持 %d×%d 格" % [MAX_MAP_SIZE.x, MAX_MAP_SIZE.y]
	return ""

func expand_to_include(region: Rect2i, padding := 2) -> String:
	ensure_layout()
	if contains_region(region):
		return ""
	var error := expansion_error(region, padding)
	if not error.is_empty():
		return error
	var old_origin := map_origin
	var old_size := map_size
	var old_columns := columns
	var expanded_bounds := _expanded_bounds(region, padding)
	var expanded_columns: Array[Dictionary] = []
	expanded_columns.resize(expanded_bounds.size.x * expanded_bounds.size.y)
	for i in expanded_columns.size():
		expanded_columns[i] = _blank_column()
	for local_y in old_size.y:
		for local_x in old_size.x:
			var logical := old_origin + Vector2i(local_x, local_y)
			var expanded_local := logical - expanded_bounds.position
			var expanded_index := expanded_local.y * expanded_bounds.size.x \
				+ expanded_local.x
			expanded_columns[expanded_index] = old_columns[
				local_y * old_size.x + local_x]
	map_origin = expanded_bounds.position
	map_size = expanded_bounds.size
	columns = expanded_columns
	format_version = FORMAT_VERSION
	emit_changed()
	return ""

func get_column(cell: Vector2i) -> Dictionary:
	if not in_bounds(cell):
		return {}
	ensure_layout()
	return columns[index(cell)]

func column_snapshot(cell: Vector2i) -> Dictionary:
	return get_column(cell).duplicate(true)

func set_column(cell: Vector2i, value: Dictionary) -> void:
	if not in_bounds(cell):
		return
	ensure_layout()
	columns[index(cell)] = _normalized_column(value)
	_normalize_anchors()
	emit_changed()

func set_columns(values: Dictionary) -> void:
	ensure_layout()
	var changed := false
	for cell: Vector2i in values:
		if not in_bounds(cell):
			continue
		var value := _normalized_column(values[cell])
		var column_index := index(cell)
		if columns[column_index] == value:
			continue
		columns[column_index] = value
		changed = true
	if changed:
		_normalize_anchors()
		emit_changed()

func layer_count(cell: Vector2i) -> int:
	var column := get_column(cell)
	return int((column.get("layers", []) as Array).size()) if not column.is_empty() else 0

func top_layer(cell: Vector2i) -> int:
	return layer_count(cell) - 1

func layer_exists(cell: Vector2i, layer: int) -> bool:
	return layer >= 0 and layer < layer_count(cell)

func get_layer(cell: Vector2i, layer: int) -> Dictionary:
	var column := get_column(cell)
	if column.is_empty():
		return {}
	var layers: Array = column.get("layers", [])
	if layer < 0 or layer >= layers.size():
		return {}
	return layers[layer]

func set_layer(cell: Vector2i, layer: int, value: Dictionary,
		support_tile_id := "") -> String:
	if not in_bounds(cell):
		return "地块超出地图边界"
	if layer < 0 or layer >= MAX_LAYERS:
		return "地块层级必须在 0～%d" % (MAX_LAYERS - 1)
	ensure_layout()
	var record := _normalized_surface(value)
	var tile := TileRegistry.find(str(record.get("tile_id", DEFAULT_SOLID_TILE)))
	if tile == null:
		return "地貌定义不存在"
	if tile != null and tile.is_water():
		return set_attachment(cell, "liquid", record, layer, support_tile_id)
	if tile != null and tile.is_overlay():
		return set_attachment(cell, "overlay", record, layer, support_tile_id)
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	var support_id := support_tile_id
	if support_id.is_empty():
		support_id = str(record.get("tile_id", DEFAULT_SOLID_TILE))
	while layers.size() <= layer:
		layers.append(_solid_record(support_id, 0))
	layers[layer] = _solid_record(
		str(record.get("tile_id", DEFAULT_SOLID_TILE)),
		int(record.get("rotation", 0)))
	column["layers"] = layers
	columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func set_layers(values: Dictionary, layer: int, support_tile_id := "") -> String:
	if layer < 0 or layer >= MAX_LAYERS:
		return "地块层级必须在 0～%d" % (MAX_LAYERS - 1)
	for cell: Vector2i in values:
		if not in_bounds(cell):
			return "地块超出地图边界"
	ensure_layout()
	for cell: Vector2i in values:
		var record: Dictionary = values[cell]
		var tile := TileRegistry.find(str(record.get("tile_id", DEFAULT_SOLID_TILE)))
		if tile == null or not tile.is_solid():
			return "批量分层绘制只接受实体地貌"
	for cell: Vector2i in values:
		var column := column_snapshot(cell)
		var layers: Array = column["layers"]
		var record: Dictionary = values[cell]
		var support_id := support_tile_id
		if support_id.is_empty():
			support_id = str(record.get("tile_id", DEFAULT_SOLID_TILE))
		while layers.size() <= layer:
			layers.append(_solid_record(support_id, 0))
		layers[layer] = _solid_record(
			str(record.get("tile_id", DEFAULT_SOLID_TILE)),
			int(record.get("rotation", 0)))
		column["layers"] = layers
		columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func remove_layer(cell: Vector2i, layer: int) -> String:
	if not layer_exists(cell, layer):
		return "目标层没有实体地块"
	if layer != top_layer(cell):
		return "只能删除最上层地块，不能在柱体中间制造悬空"
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	layers.remove_at(layer)
	column["layers"] = layers
	column["liquid"] = {}
	column["overlay"] = {}
	columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func clear_column(cell: Vector2i) -> void:
	if not in_bounds(cell):
		return
	ensure_layout()
	columns[index(cell)] = _blank_column()
	_normalize_anchors()
	emit_changed()

func get_attachment(cell: Vector2i, role: String) -> Dictionary:
	if role not in ["liquid", "overlay"]:
		return {}
	var column := get_column(cell)
	return column.get(role, {}) if not column.is_empty() else {}

func set_attachment(cell: Vector2i, role: String, value: Dictionary,
		layer := -1, support_tile_id := DEFAULT_SOLID_TILE) -> String:
	if role not in ["liquid", "overlay"]:
		return "未知附加层类型"
	if not in_bounds(cell):
		return "地块超出地图边界"
	var tile := TileRegistry.find(str(value.get("tile_id", "")))
	if tile == null or (role == "liquid" and not tile.is_water()) \
			or (role == "overlay" and not tile.is_overlay()):
		return "地貌类型与附加层不匹配"
	ensure_layout()
	var current_top := top_layer(cell)
	if current_top >= 0 and layer >= 0 and layer != current_top:
		return "液体和贴花只能附着在最高实体层"
	var target_layer := current_top if layer < 0 else layer
	if target_layer < 0:
		target_layer = 0
	if target_layer >= MAX_LAYERS:
		return "地块层级必须在 0～%d" % (MAX_LAYERS - 1)
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	while layers.size() <= target_layer:
		layers.append(_solid_record(
			support_tile_id if not support_tile_id.is_empty() else DEFAULT_SOLID_TILE,
			0))
	column["layers"] = layers
	column[role] = _normalized_surface(value)
	columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func clear_attachment(cell: Vector2i, role: String) -> void:
	if role not in ["liquid", "overlay"] or not in_bounds(cell):
		return
	ensure_layout()
	var column := column_snapshot(cell)
	column[role] = {}
	columns[index(cell)] = column
	emit_changed()

## Compatibility view of the highest visible surface.
func get_cell(cell: Vector2i) -> Dictionary:
	var column := get_column(cell)
	if column.is_empty():
		return {}
	var top := top_layer(cell)
	if top < 0:
		return _blank_cell()
	var record: Dictionary = get_layer(cell, top)
	var visible := tile_id(cell)
	var visible_record := get_attachment(cell, "liquid")
	if visible_record.is_empty():
		visible_record = record
	return {
		"exists": true,
		"terrain": TileRegistry.id_to_legacy_terrain(visible),
		"height": top,
		"tile_id": visible,
		"rotation": int(visible_record.get("rotation", record.get("rotation", 0))),
		"solid_tile_id": str(record.get("tile_id", DEFAULT_SOLID_TILE)),
		"overlay_id": overlay_tile_id(cell),
	}

## Legacy whole-column replacement used by v5 fixtures and callers.
func set_cell(cell: Vector2i, value: Dictionary) -> void:
	if not in_bounds(cell):
		return
	ensure_layout()
	_set_cell_compat(cell, value)
	_normalize_anchors()
	emit_changed()

func set_cells(values: Dictionary) -> void:
	ensure_layout()
	var changed := false
	for cell: Vector2i in values:
		if not in_bounds(cell):
			continue
		var before: Dictionary = columns[index(cell)].duplicate(true)
		_set_cell_compat(cell, values[cell])
		changed = changed or before != columns[index(cell)]
	if changed:
		_normalize_anchors()
		emit_changed()

func cell_exists(cell: Vector2i) -> bool:
	return layer_count(cell) > 0

func elevation(cell: Vector2i) -> int:
	return top_layer(cell)

func terrain_tint(tile: String) -> Color:
	var value: Variant = terrain_tints.get(tile, Color(1.0, 1.0, 1.0, 0.0))
	return value if value is Color else Color(1.0, 1.0, 1.0, 0.0)

func set_terrain_tint(tile: String, value: Color) -> void:
	if value.a <= 0.001:
		terrain_tints.erase(tile)
	else:
		terrain_tints[tile] = value
	emit_changed()

func surface_y(layer: int) -> float:
	return (layer + 1) * ELEVATION_STEP

func layer_center_y(layer: int) -> float:
	return layer * ELEVATION_STEP + ELEVATION_STEP * 0.5

func world_center(cell: Vector2i, layer := -1) -> Vector3:
	var target := elevation(cell) if layer < 0 else layer
	ensure_layout()
	return Vector3(
		grid_world_origin.x + (cell.x + 0.5) * CELL_SIZE,
		surface_y(target),
		grid_world_origin.y + (cell.y + 0.5) * CELL_SIZE)

func world_layer_center(cell: Vector2i, layer: int) -> Vector3:
	var center := world_center(cell, layer)
	center.y = layer_center_y(layer)
	return center

func world_to_cell(position: Vector3) -> Vector2i:
	ensure_layout()
	return _world_to_cell_unchecked(position)

func world_grid_point(point: Vector2i) -> Vector2:
	ensure_layout()
	return grid_world_origin + Vector2(point) * CELL_SIZE

func stair_cells(stair: Dictionary) -> PackedVector2Array:
	var low: Vector2i = stair.get("cell", Vector2i.ZERO)
	var direction: int = int(stair.get("direction", 0)) % 4
	return PackedVector2Array([low, low + DIRS[direction]])

func stair_at(cell: Vector2i) -> int:
	for i in stairs.size():
		if Vector2(cell) in stair_cells(stairs[i]):
			return i
	return -1

## Stairs replace only their upper sloping volume; solid support below remains.
func support_top_layer(cell: Vector2i) -> int:
	var stair_index := stair_at(cell)
	if stair_index < 0:
		return top_layer(cell)
	var low: Vector2i = stairs[stair_index]["cell"]
	return mini(top_layer(cell), top_layer(low))

func can_place_stair(low: Vector2i, direction: int) -> String:
	var high: Vector2i = low + DIRS[direction % 4]
	if not in_bounds(low) or not in_bounds(high):
		return "阶梯超出地图边界"
	if stair_at(low) >= 0 or stair_at(high) >= 0:
		return "阶梯与已有阶梯重叠"
	if not cell_exists(low) or not cell_exists(high):
		return "阶梯两端必须有地块"
	if elevation(high) != elevation(low) + 1:
		return "高端地块必须比低端高 2 米"
	return ""

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	ensure_layout()
	for y in map_size.y:
		for x in map_size.x:
			var cell := map_origin + Vector2i(x, y)
			var column := get_column(cell)
			var layers: Array = column.get("layers", [])
			if layers.size() > MAX_LAYERS:
				errors.append("地块 %s 超过最大层数" % cell)
			for layer in layers.size():
				var tile := TileRegistry.find(str(
					(layers[layer] as Dictionary).get("tile_id", "")))
				if tile == null or not tile.is_solid():
					errors.append("地块 %s 第 %d 层不是有效实体地貌" % [cell, layer])
			for role in ["liquid", "overlay"]:
				var attachment: Dictionary = column.get(role, {})
				if attachment.is_empty():
					continue
				if layers.is_empty():
					errors.append("地块 %s 的%s缺少实体支撑" % [cell, role])
				var tile := TileRegistry.find(str(attachment.get("tile_id", "")))
				if tile == null or (role == "liquid" and not tile.is_water()) \
						or (role == "overlay" and not tile.is_overlay()):
					errors.append("地块 %s 的附加层类型无效" % cell)
	errors.append_array(validate_content())
	return errors

## Terrain edits already validate their changed columns. Check only dependencies.
func validate_content() -> PackedStringArray:
	ensure_layout()
	var errors := PackedStringArray()
	if not in_bounds(spawn_cell) or not cell_exists(spawn_cell):
		errors.append("缺少有效的玩家出生点")
	elif spawn_layer != elevation(spawn_cell):
		errors.append("玩家出生点层锚点与最高地面不一致")
	for i in stairs.size():
		var stair := stairs[i]
		var error := can_place_stair(stair.get("cell", Vector2i(-1, -1)),
			int(stair.get("direction", 0)))
		# Ignore collision against the stair validating itself.
		if error == "阶梯与已有阶梯重叠":
			var copy := stairs.duplicate(true)
			copy.remove_at(i)
			var original := stairs
			stairs = copy
			error = can_place_stair(stair.get("cell", Vector2i(-1, -1)),
				int(stair.get("direction", 0)))
			stairs = original
		if not error.is_empty():
			errors.append("阶梯 %d：%s" % [i + 1, error])
	errors.append_array(ObjectRules.validate_all(self))
	return errors

## Copy the index, share unchanged columns, and copy only columns on write.
## This avoids deep-copying every block during each brush motion.
func fork_for_edit() -> LevelData:
	ensure_layout()
	var copy := LevelData.new()
	copy.map_size = map_size
	copy.map_origin = map_origin
	copy.grid_world_origin = grid_world_origin
	copy.has_grid_world_origin = true
	copy.format_version = FORMAT_VERSION
	copy.columns = columns.duplicate(false)
	copy.stairs = stairs.duplicate(true)
	copy.objects = objects.duplicate(true)
	copy.spawn_cell = spawn_cell
	copy.spawn_layer = spawn_layer
	copy.terrain_tints = terrain_tints
	return copy

## Read-only bounded view for chunk texture generation; world coordinates stay fixed.
func region_view(region: Rect2i) -> LevelData:
	ensure_layout()
	var bounds := region.intersection(map_bounds())
	var view := LevelData.new()
	view.map_origin = bounds.position
	view.map_size = bounds.size
	view.grid_world_origin = grid_world_origin
	view.has_grid_world_origin = true
	view.format_version = FORMAT_VERSION
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			view.columns.append(columns[index(Vector2i(x, y))])
	view.stairs = stairs
	view.terrain_tints = terrain_tints
	return view

func clone_data() -> Dictionary:
	ensure_layout()
	_normalize_anchors()
	return {
		"map_size": map_size,
		"map_origin": map_origin,
		"grid_world_origin": grid_world_origin,
		"has_grid_world_origin": has_grid_world_origin,
		"columns": columns.duplicate(true),
		"cells": [],
		"stairs": stairs.duplicate(true),
		"spawn_cell": spawn_cell,
		"spawn_layer": spawn_layer,
		"objects": objects.duplicate(true),
		"terrain_tints": terrain_tints.duplicate(true),
		"format_version": FORMAT_VERSION,
	}

func restore_data(snapshot: Dictionary) -> void:
	map_size = snapshot["map_size"]
	map_origin = snapshot.get("map_origin", Vector2i.ZERO)
	grid_world_origin = snapshot.get("grid_world_origin", Vector2.ZERO)
	has_grid_world_origin = bool(snapshot.get("has_grid_world_origin", false))
	columns.assign(snapshot.get("columns", []).duplicate(true))
	cells.assign(snapshot.get("cells", []).duplicate(true))
	stairs.assign(snapshot.get("stairs", []).duplicate(true))
	spawn_cell = snapshot.get("spawn_cell", Vector2i(-1, -1))
	spawn_layer = int(snapshot.get("spawn_layer", -1))
	objects.assign(snapshot.get("objects", []).duplicate(true))
	terrain_tints = snapshot.get("terrain_tints", {}).duplicate(true)
	format_version = int(snapshot.get("format_version", 2))
	ensure_layout()
	_normalize_anchors()
	emit_changed()

func _set_cell_compat(cell: Vector2i, value: Dictionary) -> void:
	var column_index := index(cell)
	if not bool(value.get("exists", false)):
		columns[column_index] = _blank_column()
		return
	var target := clampi(int(value.get("height", 0)), 0, MAX_LAYERS - 1)
	var id := str(value.get(
		"tile_id",
		TileRegistry.legacy_terrain_to_id(int(value.get("terrain", 0)))))
	var rotation := int(value.get("rotation", 0))
	var tile := TileRegistry.find(id)
	var role := "solid"
	if tile != null and tile.is_water():
		role = "liquid"
	elif tile != null and tile.is_overlay():
		role = "overlay"
	var column: Dictionary = columns[column_index].duplicate(true)
	var old_layers: Array = column.get("layers", [])
	var layers: Array[Dictionary] = []
	for layer in target + 1:
		if layer < old_layers.size():
			layers.append(_normalized_surface(old_layers[layer]))
		else:
			layers.append(_solid_record(
				id if role == "solid" else DEFAULT_SOLID_TILE, 0))
	if role == "solid":
		layers[target] = _solid_record(id, rotation)
		column["liquid"] = {}
		column["overlay"] = {}
	else:
		column[role] = _normalized_surface({
			"tile_id": id,
			"rotation": rotation,
		})
	column["layers"] = layers
	columns[column_index] = column

func _migrate_legacy_cells(wanted: int) -> void:
	var legacy_cells := cells.duplicate(true)
	columns.clear()
	columns.resize(wanted)
	for i in wanted:
		columns[i] = _blank_column()
		if i >= legacy_cells.size() or not legacy_cells[i] is Dictionary:
			continue
		var old: Dictionary = legacy_cells[i]
		if not bool(old.get("exists", false)):
			continue
		var target := clampi(int(old.get("height", 0)), 0, MAX_LAYERS - 1)
		var id := str(old.get(
			"tile_id",
			TileRegistry.legacy_terrain_to_id(int(old.get("terrain", 0)))))
		var rotation := int(old.get("rotation", 0))
		var tile := TileRegistry.find(id)
		var role := "solid"
		if tile != null and tile.is_water():
			role = "liquid"
		elif tile != null and tile.is_overlay():
			role = "overlay"
		var layers: Array[Dictionary] = []
		for layer in target + 1:
			layers.append(_solid_record(
				id if role == "solid" else DEFAULT_SOLID_TILE,
				rotation if role == "solid" and layer == target else 0))
		columns[i]["layers"] = layers
		if role != "solid":
			columns[i][role] = _normalized_surface({
				"tile_id": id,
				"rotation": rotation,
			})
	_migrate_anchors()
	cells.clear()

func _migrate_anchors() -> void:
	for i in objects.size():
		var record: Dictionary = objects[i]
		var old_position: Vector3 = record.get("position", Vector3.ZERO)
		var anchor_cell := _world_to_cell_unchecked(old_position)
		var anchor_layer := clampi(
			roundi(old_position.y / ELEVATION_STEP),
			0,
			maxi(top_layer(anchor_cell), 0))
		record["anchor_cell"] = anchor_cell
		record["anchor_layer"] = anchor_layer
		old_position.y += ELEVATION_STEP
		record["position"] = old_position
		objects[i] = record
	for i in stairs.size():
		var stair: Dictionary = stairs[i]
		stair["layer"] = elevation(stair.get("cell", Vector2i(-1, -1)))
		stairs[i] = stair
	spawn_layer = elevation(spawn_cell) if in_bounds(spawn_cell) \
		and cell_exists(spawn_cell) else -1

func _normalize_anchors() -> void:
	if in_bounds(spawn_cell) and cell_exists(spawn_cell):
		spawn_layer = elevation(spawn_cell)
	else:
		spawn_layer = -1
	for i in stairs.size():
		var stair: Dictionary = stairs[i]
		var low: Vector2i = stair.get("cell", Vector2i(-1, -1))
		stair["layer"] = elevation(low) if cell_exists(low) else -1
		stairs[i] = stair
	for i in objects.size():
		var record: Dictionary = objects[i]
		var position: Vector3 = record.get("position", Vector3.ZERO)
		var anchor: Vector2i = record.get(
			"anchor_cell", _world_to_cell_unchecked(position))
		if not in_bounds(anchor) or not cell_exists(anchor):
			anchor = _world_to_cell_unchecked(position)
		var anchor_layer := int(record.get("anchor_layer", -1))
		if not layer_exists(anchor, anchor_layer):
			anchor_layer = elevation(anchor) if cell_exists(anchor) else -1
		record["anchor_cell"] = anchor
		record["anchor_layer"] = anchor_layer
		objects[i] = record

func _normalized_column(value: Dictionary) -> Dictionary:
	var result := _blank_column()
	var source_layers: Array = value.get("layers", [])
	var normalized_layers: Array[Dictionary] = []
	for raw in source_layers:
		if not raw is Dictionary or normalized_layers.size() >= MAX_LAYERS:
			break
		var record := _normalized_surface(raw)
		var tile := TileRegistry.find(str(record.get("tile_id", DEFAULT_SOLID_TILE)))
		if tile != null and not tile.is_solid():
			record = _solid_record(DEFAULT_SOLID_TILE, 0)
		normalized_layers.append(record)
	result["layers"] = normalized_layers
	if not normalized_layers.is_empty():
		for role in ["liquid", "overlay"]:
			var attachment: Variant = value.get(role, {})
			if attachment is Dictionary and not attachment.is_empty():
				result[role] = _normalized_surface(attachment)
	return result

func _normalized_surface(value: Dictionary) -> Dictionary:
	return {
		"tile_id": str(value.get(
			"tile_id",
			TileRegistry.legacy_terrain_to_id(int(value.get("terrain", 0))))),
		"rotation": posmod(int(value.get("rotation", 0)), 4),
	}

func _solid_record(tile_id: String, rotation: int) -> Dictionary:
	var tile := TileRegistry.find(tile_id)
	var id := tile_id
	if tile == null or not tile.is_solid():
		id = DEFAULT_SOLID_TILE
	return {
		"tile_id": id,
		"rotation": posmod(rotation, 4),
	}

func _world_to_cell_unchecked(position: Vector3) -> Vector2i:
	return Vector2i(
		floori((position.x - grid_world_origin.x) / CELL_SIZE),
		floori((position.z - grid_world_origin.y) / CELL_SIZE))

func _expanded_bounds(region: Rect2i, padding: int) -> Rect2i:
	var current := map_bounds()
	var first := current.position
	var last := current.end
	if region.position.x < current.position.x:
		first.x = region.position.x - padding
	if region.position.y < current.position.y:
		first.y = region.position.y - padding
	if region.end.x > current.end.x:
		last.x = region.end.x + padding
	if region.end.y > current.end.y:
		last.y = region.end.y + padding
	return Rect2i(first, last - first)

func _blank_column() -> Dictionary:
	return {
		"layers": [],
		"liquid": {},
		"overlay": {},
	}

func _blank_cell() -> Dictionary:
	return {
		"exists": false,
		"terrain": TERRAIN_GRASS,
		"height": 0,
		"tile_id": DEFAULT_SOLID_TILE,
		"rotation": 0,
	}
