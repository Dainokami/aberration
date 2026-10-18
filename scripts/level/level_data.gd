@tool
class_name LevelData
extends Resource

const CELL_SIZE := 2.0
const ELEVATION_STEP := 2.0
const BASE_Y := 0.0
const TERRAIN_GRASS := 0
const TERRAIN_ROCK := 1
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FORMAT_VERSION := 9
const MAX_MAP_SIZE := Vector2i(600, 600)
const MAX_LAYERS := 32
const DEFAULT_SOLID_TILE := "grass"

@export var map_size := Vector2i(16, 16)
## Minimum logical cell coordinate covered by the editable map bounds.
@export var map_origin := Vector2i.ZERO
## World-space corner of logical cell (0, 0), independent from map bounds.
@export var grid_world_origin := Vector2.ZERO
@export var has_grid_world_origin := false
## Stable height slots: an empty dictionary is air, never a missing support to fill.
## Solid and water blocks occupy separate slots. Only solids own overlays.
@export var columns: Array[Dictionary] = []
## Legacy v5 payload. It is consumed and cleared by ensure_layout().
@export var cells: Array[Dictionary] = []
@export var stairs: Array[Dictionary] = []
@export var spawn_cell := Vector2i(-1, -1)
@export var spawn_layer := -1
@export var format_version := 5
@export var objects: Array[Dictionary] = []
## Non-colliding decoration instances. Stored separately from gameplay objects.
@export var details: Array[Dictionary] = []
## Per-map color overrides. Alpha is tint strength; RGB is the target hue.
@export var terrain_tints: Dictionary = {}
## Generation provenance and per-cell zone labels; edits retain the original recipe.
@export var generation: Dictionary = {}
@export var encounter: EncounterConfig
## Sparse authored region overrides keyed by Vector3i(x, support_layer, z).
@export var encounter_regions: Dictionary = {}

var _ensuring_layout := false
## Read-only surface views share the source columns for terrain art generation.
var _surface_layer := -1

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
	details.clear()
	terrain_tints.clear()
	generation.clear()
	encounter = null
	encounter_regions.clear()
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
		if format_version < 6:
			_migrate_anchors()
	cells.clear()
	format_version = FORMAT_VERSION
	_normalize_anchors()
	_ensuring_layout = false

func tile_id(cell: Vector2i, layer := -1) -> String:
	if layer >= 0:
		return str(get_layer(cell, layer).get("tile_id", DEFAULT_SOLID_TILE))
	var target := top_layer(cell)
	return str(get_layer(cell, target).get("tile_id", DEFAULT_SOLID_TILE))

func solid_tile_id(cell: Vector2i, layer := -1) -> String:
	var target := top_layer(cell) if layer < 0 else layer
	return str(get_layer(cell, target).get("tile_id", DEFAULT_SOLID_TILE))

func overlay_tile_id(cell: Vector2i, layer := -1) -> String:
	var overlay := get_attachment(cell, "overlay", layer)
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
	resize_bounds(_expanded_bounds(region, padding))
	return ""

## Reindex existing column references without cloning the entire terrain.
## Used by expansion undo as well as growth; world coordinates remain fixed.
func resize_bounds(bounds: Rect2i) -> void:
	ensure_layout()
	if bounds == map_bounds():
		return
	var old_origin := map_origin
	var old_size := map_size
	var old_columns := columns
	var expanded_bounds := bounds
	var expanded_columns: Array[Dictionary] = []
	expanded_columns.resize(expanded_bounds.size.x * expanded_bounds.size.y)
	for i in expanded_columns.size():
		expanded_columns[i] = _blank_column()
	var retained := Rect2i(old_origin, old_size).intersection(bounds)
	for y in range(retained.position.y, retained.end.y):
		for x in range(retained.position.x, retained.end.x):
			var logical := Vector2i(x, y)
			var expanded_local := logical - expanded_bounds.position
			var expanded_index := expanded_local.y * expanded_bounds.size.x \
				+ expanded_local.x
			var old_local := logical - old_origin
			expanded_columns[expanded_index] = old_columns[
				old_local.y * old_size.x + old_local.x]
	map_origin = expanded_bounds.position
	map_size = expanded_bounds.size
	columns = expanded_columns
	format_version = FORMAT_VERSION
	emit_changed()

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
	if _surface_layer >= 0:
		return _surface_layer if is_surface_exposed(cell, _surface_layer) else -1
	return layer_count(cell) - 1

func layer_exists(cell: Vector2i, layer: int) -> bool:
	return not get_layer(cell, layer).is_empty()

func is_water_layer(cell: Vector2i, layer: int) -> bool:
	var tile := TileRegistry.find(str(get_layer(cell, layer).get("tile_id", "")))
	return tile != null and tile.is_water()

func is_solid_layer(cell: Vector2i, layer: int) -> bool:
	var tile := TileRegistry.find(str(get_layer(cell, layer).get("tile_id", "")))
	return tile != null and tile.is_solid()

func is_surface_exposed(cell: Vector2i, layer: int) -> bool:
	return layer_exists(cell, layer) and not is_solid_layer(cell, layer + 1) \
		and (not is_water_layer(cell, layer) or not is_water_layer(cell, layer + 1))

func exposed_layers(cell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var layers: Array = get_column(cell).get("layers", [])
	for layer in layers.size():
		if is_surface_exposed(cell, layer):
			result.append(layer)
	return result

## A surface hit specifies the height; never silently snap to the highest block.
func layer_at_surface(position: Vector3) -> int:
	return roundi(position.y / ELEVATION_STEP) - 1

func world_to_block(position: Vector3) -> Vector3i:
	var cell := world_to_cell(position)
	return Vector3i(cell.x, floori(position.y / ELEVATION_STEP), cell.y)

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
	if tile != null and tile.is_overlay():
		return set_attachment(cell, "overlay", record, layer, support_tile_id)
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	while layers.size() <= layer:
		layers.append({})
	if layer_exists(cell, layer) and is_water_layer(cell, layer) != tile.is_water():
		ObjectRules.remove_terrain_support(self, cell, layer)
	var replacement := record
	if tile.is_solid() and is_solid_layer(cell, layer):
		replacement = (layers[layer] as Dictionary).duplicate(true)
		replacement.merge(record, true)
	layers[layer] = replacement
	column["layers"] = layers
	columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func set_layers(values: Dictionary, layer: int, _support_tile_id := "") -> String:
	if layer < 0 or layer >= MAX_LAYERS:
		return "地块层级必须在 0～%d" % (MAX_LAYERS - 1)
	for cell: Vector2i in values:
		if not in_bounds(cell):
			return "地块超出地图边界"
	ensure_layout()
	for cell: Vector2i in values:
		var record: Dictionary = values[cell]
		var tile := TileRegistry.find(str(record.get("tile_id", DEFAULT_SOLID_TILE)))
		if tile == null or not tile.is_block():
			return "批量分层绘制只接受实体或海水地块"
	for cell: Vector2i in values:
		var column := column_snapshot(cell)
		var layers: Array = column["layers"]
		var record: Dictionary = values[cell]
		while layers.size() <= layer:
			layers.append({})
		var replacement := _normalized_surface(record)
		if is_solid_layer(cell, layer) and not tile_is_water(record):
			replacement = (layers[layer] as Dictionary).duplicate(true)
			replacement.merge(_normalized_surface(record), true)
		layers[layer] = replacement
		column["layers"] = layers
		columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func remove_layer(cell: Vector2i, layer: int) -> String:
	if not layer_exists(cell, layer):
		return "目标层没有实体地块"
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	layers[layer] = {}
	while not layers.is_empty() and (layers.back() as Dictionary).is_empty():
		layers.pop_back()
	column["layers"] = layers
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

func get_attachment(cell: Vector2i, role: String, layer := -1) -> Dictionary:
	if role not in ["liquid", "overlay"]:
		return {}
	var target := top_layer(cell) if layer < 0 else layer
	if role == "liquid":
		if is_water_layer(cell, target):
			return get_layer(cell, target)
		if is_water_layer(cell, target + 1):
			return get_layer(cell, target + 1)
		return {}
	return get_layer(cell, target).get(role, {})

func set_attachment(cell: Vector2i, role: String, value: Dictionary,
		layer := -1, _support_tile_id := DEFAULT_SOLID_TILE) -> String:
	if role not in ["liquid", "overlay"]:
		return "未知附加层类型"
	if not in_bounds(cell):
		return "地块超出地图边界"
	var tile := TileRegistry.find(str(value.get("tile_id", "")))
	if tile == null or (role == "liquid" and not tile.is_water()) \
			or (role == "overlay" and not tile.is_overlay()):
		return "地貌类型与附加层不匹配"
	ensure_layout()
	var target_layer := top_layer(cell) if layer < 0 else layer
	if role == "liquid":
		var water_layer := target_layer if is_water_layer(cell, target_layer) else target_layer + 1
		if layer_exists(cell, water_layer) and not is_water_layer(cell, water_layer):
			return "目标层已被其他地块占用"
		return set_layer(cell, water_layer, value)
	if not is_solid_layer(cell, target_layer) or not is_surface_exposed(cell, target_layer):
		return "贴花需要一个外露的实体顶面"
	var column := column_snapshot(cell)
	var layers: Array = column["layers"]
	layers[target_layer][role] = _normalized_surface(value)
	column["layers"] = layers
	columns[index(cell)] = column
	_normalize_anchors()
	emit_changed()
	return ""

func clear_attachment(cell: Vector2i, role: String, layer := -1) -> void:
	if role not in ["liquid", "overlay"] or not in_bounds(cell):
		return
	var target := top_layer(cell) if layer < 0 else layer
	if role == "liquid":
		if is_water_layer(cell, target):
			remove_layer(cell, target)
		elif is_water_layer(cell, target + 1):
			remove_layer(cell, target + 1)
		return
	if not layer_exists(cell, target):
		return
	var column := column_snapshot(cell)
	column["layers"][target].erase(role)
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
	var visible_record := record
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
	return top_layer(cell) >= 0

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

func stair_at(cell: Vector2i, layer := -1) -> int:
	var target := _surface_layer if layer < 0 else layer
	for i in stairs.size():
		if Vector2(cell) in stair_cells(stairs[i]):
			var low: Vector2i = stairs[i]["cell"]
			var base := int(stairs[i].get("layer", top_layer(low)))
			if target >= 0 and target != base + (0 if cell == low else 1):
				continue
			return i
	return -1

## Stairs replace only their upper sloping volume; solid support below remains.
func support_top_layer(cell: Vector2i) -> int:
	var stair_index := stair_at(cell)
	if stair_index < 0:
		return top_layer(cell)
	var low: Vector2i = stairs[stair_index]["cell"]
	return mini(top_layer(cell), int(stairs[stair_index].get("layer", top_layer(low))))

func has_terrain_volume(cell: Vector2i, layer: int) -> bool:
	if not is_solid_layer(cell, layer):
		return false
	var stair_index := stair_at(cell, layer)
	return stair_index < 0 or cell == Vector2i(stairs[stair_index]["cell"])

func can_place_stair(low: Vector2i, direction: int, layer := -1) -> String:
	var high: Vector2i = low + DIRS[direction % 4]
	var base := top_layer(low) if layer < 0 else layer
	if not in_bounds(low) or not in_bounds(high):
		return "阶梯超出地图边界"
	if stair_at(low, base) >= 0 or stair_at(high, base + 1) >= 0:
		return "阶梯与已有阶梯重叠"
	if not is_solid_layer(low, base) or not is_solid_layer(high, base + 1):
		return "阶梯两端必须有地块"
	if not is_surface_exposed(low, base) or not is_surface_exposed(high, base + 1):
		return "阶梯两端必须是相差 2 米的外露顶面"
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
				if (layers[layer] as Dictionary).is_empty():
					continue
				var tile := TileRegistry.find(str(
					(layers[layer] as Dictionary).get("tile_id", "")))
				if tile == null or not tile.is_block():
					errors.append("地块 %s 第 %d 层不是有效地貌" % [cell, layer])
				for role in ["liquid", "overlay"]:
					var attachment: Dictionary = layers[layer].get(role, {})
					if attachment.is_empty():
						continue
					var attachment_tile := TileRegistry.find(str(attachment.get("tile_id", "")))
					if attachment_tile == null or (role == "liquid" and not attachment_tile.is_water()) \
							or (role == "overlay" and not attachment_tile.is_overlay()):
						errors.append("地块 %s 第 %d 层的附加层类型无效" % [cell, layer])
	errors.append_array(validate_content())
	if layer_exists(spawn_cell, spawn_layer) and not is_surface_exposed(spawn_cell, spawn_layer):
		errors.append("玩家出生点被上方地块覆盖，请重新选择外露顶面")
	return errors

## Terrain edits already validate their changed columns. Check only dependencies.
func validate_content(check_assets := true) -> PackedStringArray:
	ensure_layout()
	var errors := PackedStringArray()
	if not in_bounds(spawn_cell) or not is_solid_layer(spawn_cell, spawn_layer):
		errors.append("缺少有效的玩家出生点")
	for i in stairs.size():
		var stair := stairs[i]
		var error := can_place_stair(stair.get("cell", Vector2i(-1, -1)),
			int(stair.get("direction", 0)), int(stair.get("layer", -1)))
		# Ignore collision against the stair validating itself.
		if error == "阶梯与已有阶梯重叠":
			var copy := stairs.duplicate(true)
			copy.remove_at(i)
			var original := stairs
			stairs = copy
			error = can_place_stair(stair.get("cell", Vector2i(-1, -1)),
				int(stair.get("direction", 0)), int(stair.get("layer", -1)))
			stairs = original
		if not error.is_empty():
			errors.append("阶梯 %d：%s" % [i + 1, error])
	errors.append_array(ObjectRules.validate_all(self, check_assets))
	errors.append_array(DetailRules.validate_all(self, check_assets))
	errors.append_array(EncounterRegions.errors(self))
	if encounter != null and encounter.enabled:
		errors.append_array(encounter.errors())
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
	copy.details = details.duplicate(true)
	copy.spawn_cell = spawn_cell
	copy.spawn_layer = spawn_layer
	copy.terrain_tints = terrain_tints
	copy.generation = generation.duplicate(true)
	copy.encounter = encounter.duplicate(true) as EncounterConfig if encounter != null else null
	copy.encounter_regions = encounter_regions.duplicate(true)
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
	view._surface_layer = _surface_layer
	return view

## Reuse the terrain art pipeline at one exposed height without copying columns.
## Only query methods may be called on this view.
func surface_view(layer: int) -> LevelData:
	ensure_layout()
	var view := LevelData.new()
	view.map_origin = map_origin
	view.map_size = map_size
	view.grid_world_origin = grid_world_origin
	view.has_grid_world_origin = true
	view.format_version = FORMAT_VERSION
	view.columns = columns
	view.stairs = stairs
	view.terrain_tints = terrain_tints
	view._surface_layer = layer
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
		"details": details.duplicate(true),
		"terrain_tints": terrain_tints.duplicate(true),
		"generation": generation.duplicate(true),
		"encounter": encounter.snapshot() if encounter != null else null,
		"encounter_regions": encounter_regions.duplicate(true),
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
	details.assign(snapshot.get("details", []).duplicate(true))
	terrain_tints = snapshot.get("terrain_tints", {}).duplicate(true)
	generation = snapshot.get("generation", {}).duplicate(true)
	var encounter_values: Variant = snapshot.get("encounter")
	encounter = EncounterConfig.from_snapshot(encounter_values.duplicate(true)) \
		if encounter_values is Dictionary else null
	encounter_regions = snapshot.get("encounter_regions", {}).duplicate(true)
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
	if tile != null and tile.is_water():
		var water_layers: Array[Dictionary] = []
		for layer in target + 1:
			water_layers.append(_normalized_surface({"tile_id": id, "rotation": rotation}))
		columns[column_index] = {"layers": water_layers}
		return
	var role := "solid"
	if tile != null and tile.is_water():
		role = "liquid"
	elif tile != null and tile.is_overlay():
		role = "overlay"
	var column: Dictionary = columns[column_index].duplicate(true)
	var old_layers: Array = column.get("layers", [])
	var layers: Array[Dictionary] = []
	for layer in target + 1:
		if layer < old_layers.size() and is_solid_layer(cell, layer):
			layers.append((old_layers[layer] as Dictionary).duplicate(true))
		else:
			layers.append(_solid_record(
				id if role == "solid" else DEFAULT_SOLID_TILE, 0))
	if role == "solid":
		layers[target] = _solid_record(id, rotation)
	else:
		layers[target][role] = _normalized_surface({
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
			layers[target][role] = _normalized_surface({
				"tile_id": id,
				"rotation": rotation,
			})
		columns[i] = _normalized_column(columns[i])
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
	if spawn_layer < 0 and in_bounds(spawn_cell) and cell_exists(spawn_cell):
		spawn_layer = elevation(spawn_cell)
	elif not in_bounds(spawn_cell):
		spawn_layer = -1
	for i in stairs.size():
		var stair: Dictionary = stairs[i]
		var low: Vector2i = stair.get("cell", Vector2i(-1, -1))
		if not stair.has("layer"):
			stair["layer"] = elevation(low) if cell_exists(low) else -1
		stairs[i] = stair
	for i in objects.size():
		var record: Dictionary = objects[i]
		record["anchor_kind"] = str(record.get("anchor_kind", "top"))
		if record["anchor_kind"] != "top":
			objects[i] = record
			continue
		var position: Vector3 = record.get("position", Vector3.ZERO)
		var anchor: Vector2i = record.get(
			"anchor_cell", _world_to_cell_unchecked(position))
		if not in_bounds(anchor) or not cell_exists(anchor):
			anchor = _world_to_cell_unchecked(position)
		var anchor_layer := int(record.get("anchor_layer", -1))
		if anchor_layer < 0:
			anchor_layer = layer_at_surface(position)
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
		if raw.is_empty():
			normalized_layers.append({})
			continue
		var record := _normalized_surface(raw)
		var tile := TileRegistry.find(str(record.get("tile_id", DEFAULT_SOLID_TILE)))
		if tile != null and not tile.is_block():
			record = _solid_record(DEFAULT_SOLID_TILE, 0)
		for role in ["liquid", "overlay"]:
			var attachment: Dictionary = raw.get(role, {})
			if not attachment.is_empty():
				record[role] = _normalized_surface(attachment)
		normalized_layers.append(record)
	while not normalized_layers.is_empty() and normalized_layers.back().is_empty():
		normalized_layers.pop_back()
	result["layers"] = normalized_layers
	if not normalized_layers.is_empty():
		for role in ["liquid", "overlay"]:
			var attachment: Variant = value.get(role, {})
			if attachment is Dictionary and not attachment.is_empty():
				normalized_layers.back()[role] = _normalized_surface(attachment)
	# v6-v8 liquids lived on a solid surface. Preserve that seabed and place
	# a genuine water volume above it; never overwrite an existing block.
	for layer in normalized_layers.size():
		var liquid: Dictionary = normalized_layers[layer].get("liquid", {})
		normalized_layers[layer].erase("liquid")
		if liquid.is_empty():
			continue
		var target := layer + 1
		while target < normalized_layers.size() and not normalized_layers[target].is_empty():
			target += 1
		while normalized_layers.size() <= target:
			normalized_layers.append({})
		normalized_layers[target] = liquid
	return result

func tile_is_water(record: Dictionary) -> bool:
	var tile := TileRegistry.find(str(record.get("tile_id", "")))
	return tile != null and tile.is_water()

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
	# Reserve only the padding which fits. A valid edge cell must remain
	# reachable even when the optional two-cell margin would exceed the limit.
	for axis in 2:
		if last[axis] - first[axis] <= MAX_MAP_SIZE[axis]:
			continue
		var required_first := mini(current.position[axis], region.position[axis])
		var required_last := maxi(current.end[axis], region.end[axis])
		if required_last - required_first > MAX_MAP_SIZE[axis]:
			continue
		var available := MAX_MAP_SIZE[axis] - (required_last - required_first)
		var before := mini(required_first - first[axis], available)
		first[axis] = required_first - before
		last[axis] = required_last + mini(last[axis] - required_last, available - before)
	return Rect2i(first, last - first)

func _blank_column() -> Dictionary:
	return {
		"layers": [],
	}

func _blank_cell() -> Dictionary:
	return {
		"exists": false,
		"terrain": TERRAIN_GRASS,
		"height": 0,
		"tile_id": DEFAULT_SOLID_TILE,
		"rotation": 0,
	}
