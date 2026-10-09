@tool
class_name LevelData
extends Resource

const CELL_SIZE := 2.0
const ELEVATION_STEP := 2.0
const BASE_Y := -2.0
const TERRAIN_GRASS := 0
const TERRAIN_ROCK := 1
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

@export var map_size := Vector2i(16, 16)
@export var cells: Array[Dictionary] = []
@export var stairs: Array[Dictionary] = []
@export var spawn_cell := Vector2i(-1, -1)
@export var format_version := 2
@export var objects: Array[Dictionary] = []

func setup_blank(size := Vector2i(16, 16)) -> void:
	map_size = size
	cells.clear()
	cells.resize(size.x * size.y)
	for i in cells.size():
		cells[i] = {"exists": false, "terrain": TERRAIN_GRASS, "height": 0}
	stairs.clear()
	objects.clear()
	spawn_cell = Vector2i(-1, -1)

func ensure_layout() -> void:
	var wanted := map_size.x * map_size.y
	if cells.size() == wanted:
		return
	var old := cells.duplicate(true)
	cells.resize(wanted)
	for i in wanted:
		cells[i] = old[i] if i < old.size() and old[i] is Dictionary else {
			"exists": false, "terrain": TERRAIN_GRASS, "height": 0}

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y

func index(cell: Vector2i) -> int:
	return cell.y * map_size.x + cell.x

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

func cell_exists(cell: Vector2i) -> bool:
	return bool(get_cell(cell).get("exists", false))

func elevation(cell: Vector2i) -> int:
	return int(get_cell(cell).get("height", 0))

func world_center(cell: Vector2i, level := -1) -> Vector3:
	var h := elevation(cell) if level < 0 else level
	var origin := -Vector2(map_size) * CELL_SIZE * 0.5
	return Vector3(origin.x + (cell.x + 0.5) * CELL_SIZE, h * ELEVATION_STEP,
		origin.y + (cell.y + 0.5) * CELL_SIZE)

func world_to_cell(position: Vector3) -> Vector2i:
	var origin := -Vector2(map_size) * CELL_SIZE * 0.5
	return Vector2i(floori((position.x - origin.x) / CELL_SIZE),
		floori((position.z - origin.y) / CELL_SIZE))

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
		"cells": cells.duplicate(true),
		"stairs": stairs.duplicate(true),
		"spawn_cell": spawn_cell,
		"objects": objects.duplicate(true),
		"format_version": format_version,
	}

func restore_data(snapshot: Dictionary) -> void:
	map_size = snapshot["map_size"]
	cells = snapshot["cells"].duplicate(true)
	stairs = snapshot["stairs"].duplicate(true)
	spawn_cell = snapshot["spawn_cell"]
	objects.assign(snapshot.get("objects", []).duplicate(true))
	format_version = int(snapshot.get("format_version", 2))
	emit_changed()
