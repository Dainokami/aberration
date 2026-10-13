@tool
class_name LevelData
extends Resource

const CELL_SIZE := 2.0
const ELEVATION_STEP := 2.0
const BASE_Y := -2.0
const TERRAIN_GRASS := 0
const TERRAIN_ROCK := 1
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const FORMAT_VERSION := 5
const MAX_MAP_SIZE := Vector2i(128, 128)

@export var map_size := Vector2i(16, 16)
## Minimum logical cell coordinate covered by the editable map bounds.
@export var map_origin := Vector2i.ZERO
## World-space corner of logical cell (0, 0), independent from map bounds.
@export var grid_world_origin := Vector2.ZERO
@export var has_grid_world_origin := false
@export var cells: Array[Dictionary] = []
@export var stairs: Array[Dictionary] = []
@export var spawn_cell := Vector2i(-1, -1)
@export var format_version := 4
@export var objects: Array[Dictionary] = []
## Per-map color overrides. Alpha is tint strength; RGB is the target hue.
@export var terrain_tints: Dictionary = {}

func setup_blank(size := Vector2i(16, 16)) -> void:
	map_size = size
	map_origin = Vector2i.ZERO
	grid_world_origin = -Vector2(size) * CELL_SIZE * 0.5
	has_grid_world_origin = true
	cells.clear()
	cells.resize(size.x * size.y)
	for i in cells.size():
		cells[i] = _blank_cell()
	stairs.clear()
	objects.clear()
	terrain_tints.clear()
	spawn_cell = Vector2i(-1, -1)
	format_version = FORMAT_VERSION

func ensure_layout() -> void:
	var wanted := map_size.x * map_size.y
	if cells.size() == wanted and format_version >= FORMAT_VERSION \
			and has_grid_world_origin:
		return
	if not has_grid_world_origin:
		grid_world_origin = -Vector2(map_size) * CELL_SIZE * 0.5
		has_grid_world_origin = true
	var old_size := cells.size()
	cells.resize(wanted)
	for i in wanted:
		if i < old_size and cells[i] is Dictionary:
			var c: Dictionary = cells[i]
			if not c.has("tile_id"):
				c["tile_id"] = "rock" if int(c.get("terrain", 0)) == TERRAIN_ROCK else "grass"
			if not c.has("rotation"):
				c["rotation"] = 0
			cells[i] = c
		else:
			cells[i] = _blank_cell()
	format_version = maxi(format_version, FORMAT_VERSION)

func tile_id(cell: Vector2i) -> String:
	var value := get_cell(cell)
	return str(value.get(
		"tile_id",
		"rock" if int(value.get("terrain", 0)) == TERRAIN_ROCK else "grass"))

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
	var old_cells := cells
	var expanded_bounds := _expanded_bounds(region, padding)
	var expanded_cells: Array[Dictionary] = []
	expanded_cells.resize(expanded_bounds.size.x * expanded_bounds.size.y)
	for i in expanded_cells.size():
		expanded_cells[i] = _blank_cell()
	for local_y in old_size.y:
		for local_x in old_size.x:
			var logical := old_origin + Vector2i(local_x, local_y)
			var expanded_local := logical - expanded_bounds.position
			var expanded_index := expanded_local.y * expanded_bounds.size.x \
				+ expanded_local.x
			expanded_cells[expanded_index] = old_cells[
				local_y * old_size.x + local_x]
	map_origin = expanded_bounds.position
	map_size = expanded_bounds.size
	cells = expanded_cells
	format_version = FORMAT_VERSION
	emit_changed()
	return ""

func get_cell(cell: Vector2i) -> Dictionary:
	if not in_bounds(cell):
		return {}
	ensure_layout()
	return cells[index(cell)]

func set_cell(cell: Vector2i, value: Dictionary) -> void:
	if not in_bounds(cell):
		return
	ensure_layout()
	cells[index(cell)] = value.duplicate(true)
	emit_changed()

func set_cells(values: Dictionary) -> void:
	ensure_layout()
	var changed := false
	for cell: Vector2i in values:
		if not in_bounds(cell):
			continue
		var value: Dictionary = values[cell]
		var cell_index := index(cell)
		if cells[cell_index] == value:
			continue
		cells[cell_index] = value.duplicate(true)
		changed = true
	if changed:
		emit_changed()

func cell_exists(cell: Vector2i) -> bool:
	return bool(get_cell(cell).get("exists", false))

func elevation(cell: Vector2i) -> int:
	return int(get_cell(cell).get("height", 0))

func terrain_tint(tile: String) -> Color:
	var value: Variant = terrain_tints.get(tile, Color(1.0, 1.0, 1.0, 0.0))
	return value if value is Color else Color(1.0, 1.0, 1.0, 0.0)

func set_terrain_tint(tile: String, value: Color) -> void:
	if value.a <= 0.001:
		terrain_tints.erase(tile)
	else:
		terrain_tints[tile] = value
	emit_changed()

func world_center(cell: Vector2i, level := -1) -> Vector3:
	var h := elevation(cell) if level < 0 else level
	ensure_layout()
	return Vector3(
		grid_world_origin.x + (cell.x + 0.5) * CELL_SIZE,
		h * ELEVATION_STEP,
		grid_world_origin.y + (cell.y + 0.5) * CELL_SIZE)

func world_to_cell(position: Vector3) -> Vector2i:
	ensure_layout()
	return Vector2i(
		floori((position.x - grid_world_origin.x) / CELL_SIZE),
		floori((position.z - grid_world_origin.y) / CELL_SIZE))

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
	if not in_bounds(spawn_cell) or not cell_exists(spawn_cell):
		errors.append("缺少有效的玩家出生点")
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

func clone_data() -> Dictionary:
	return {
		"map_size": map_size,
		"map_origin": map_origin,
		"grid_world_origin": grid_world_origin,
		"has_grid_world_origin": has_grid_world_origin,
		"cells": cells.duplicate(true),
		"stairs": stairs.duplicate(true),
		"spawn_cell": spawn_cell,
		"objects": objects.duplicate(true),
		"terrain_tints": terrain_tints.duplicate(true),
		"format_version": format_version,
	}

func restore_data(snapshot: Dictionary) -> void:
	map_size = snapshot["map_size"]
	map_origin = snapshot.get("map_origin", Vector2i.ZERO)
	grid_world_origin = snapshot.get("grid_world_origin", Vector2.ZERO)
	has_grid_world_origin = bool(snapshot.get("has_grid_world_origin", false))
	cells = snapshot["cells"].duplicate(true)
	stairs = snapshot["stairs"].duplicate(true)
	spawn_cell = snapshot["spawn_cell"]
	objects.assign(snapshot.get("objects", []).duplicate(true))
	terrain_tints = snapshot.get("terrain_tints", {}).duplicate(true)
	format_version = int(snapshot.get("format_version", 2))
	emit_changed()

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

func _blank_cell() -> Dictionary:
	return {
		"exists": false,
		"terrain": TERRAIN_GRASS,
		"height": 0,
		"tile_id": "grass",
		"rotation": 0,
	}
