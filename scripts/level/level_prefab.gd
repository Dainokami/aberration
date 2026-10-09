@tool
class_name LevelPrefab
extends Resource

@export var display_name := "营地"
@export var fragment: LevelData
@export var version := 1

static func capture(source: LevelData, region: Rect2i) -> Dictionary:
	if region.size.x <= 0 or region.size.y <= 0 or not source.in_bounds(region.position) or not source.in_bounds(region.end - Vector2i.ONE):
		return {"error": "选区超出地图"}
	var prefab := LevelPrefab.new()
	prefab.fragment = LevelData.new()
	prefab.fragment.setup_blank(region.size)
	var target := prefab.fragment
	for y in region.size.y:
		for x in region.size.x:
			var local := Vector2i(x, y)
			target.set_cell(local, source.get_cell(region.position + local))
	for stair in source.stairs:
		var low: Vector2i = stair["cell"]
		var high: Vector2i = low + LevelData.DIRS[int(stair["direction"])]
		if region.has_point(low) != region.has_point(high):
			return {"error": "选区切断阶梯，请完整包含或避开"}
		if region.has_point(low):
			target.stairs.append({"cell": low - region.position, "direction": stair["direction"]})
	for record in source.objects:
		var inside := false
		var outside := false
		for cell in ObjectRules.covered_cells(source, record):
			inside = inside or region.has_point(cell)
			outside = outside or not region.has_point(cell)
		if inside and outside:
			return {"error": "选区切断物件碰撞占地"}
		if not inside:
			continue
		var copy := record.duplicate(true)
		var anchor := source.world_to_cell(record["position"])
		copy["position"] = target.world_center(anchor - region.position) + (record["position"] - source.world_center(anchor))
		target.objects.append(copy)
	# Player spawn is deliberately not captured: each level has exactly one.
	return {"error": "", "prefab": prefab}

func rotated_size(turns: int) -> Vector2i:
	return fragment.map_size if posmod(turns, 2) == 0 else Vector2i(fragment.map_size.y, fragment.map_size.x)

func rotate_cell(cell: Vector2i, turns: int) -> Vector2i:
	var size := fragment.map_size
	for step in posmod(turns, 4):
		cell = Vector2i(size.y - 1 - cell.y, cell.x)
		size = Vector2i(size.y, size.x)
	return cell

## Build a candidate snapshot first. Caller commits once, only after all checks pass.
func stamp(destination: LevelData, anchor: Vector2i, turns: int, objects_only := false) -> Dictionary:
	if fragment == null:
		return {"error": "预制数据缺失"}
	var area := Rect2i(anchor, rotated_size(turns))
	if not destination.in_bounds(anchor) or not destination.in_bounds(area.end - Vector2i.ONE):
		return {"error": "预制超出地图"}
	var candidate := LevelData.new()
	candidate.restore_data(destination.clone_data())
	if not objects_only:
		if area.has_point(candidate.spawn_cell):
			return {"error": "预制覆盖玩家出生点，请先移动出生点"}
		for stair in candidate.stairs:
			for cell: Vector2 in candidate.stair_cells(stair):
				if area.has_point(Vector2i(cell)):
					return {"error": "预制覆盖已有阶梯，请先删除"}
		for record in candidate.objects:
			for cell in ObjectRules.covered_cells(candidate, record):
				if area.has_point(cell):
					return {"error": "预制覆盖已有物件，请先移动或删除"}
		for y in fragment.map_size.y:
			for x in fragment.map_size.x:
				var cell := Vector2i(x, y)
				candidate.set_cell(anchor + rotate_cell(cell, turns), fragment.get_cell(cell))
		for stair in fragment.stairs:
			candidate.stairs.append({"cell": anchor + rotate_cell(stair["cell"], turns),
				"direction": posmod(int(stair["direction"]) + turns, 4)})
	var rotation_basis := Basis(Vector3.UP, -posmod(turns, 4) * PI * 0.5)
	for record in fragment.objects:
		var copy := record.duplicate(true)
		var old_cell := fragment.world_to_cell(record["position"])
		var new_cell := anchor + rotate_cell(old_cell, turns)
		var offset: Vector3 = record["position"] - fragment.world_center(old_cell)
		copy["position"] = candidate.world_center(new_cell) + rotation_basis * offset
		copy["yaw"] = float(copy.get("yaw", 0.0)) - posmod(turns, 4) * PI * 0.5
		copy["id"] = ObjectRules.new_id()
		var error := ObjectRules.validate_record(candidate, copy)
		if not error.is_empty():
			return {"error": error}
		candidate.objects.append(copy)
	# Validate stairs without requiring a spawn point on a work-in-progress map.
	var errors := candidate.validate()
	if not errors.is_empty() and errors[0] == "缺少有效的玩家出生点":
		errors.remove_at(0)
	if not errors.is_empty():
		return {"error": "\n".join(errors)}
	return {"error": "", "snapshot": candidate.clone_data()}
